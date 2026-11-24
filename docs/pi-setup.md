# Raspberry Pi setup, from scratch

Do one step, run its check, compare with "Expect", then go on. Each step is safe to repeat.
Nothing here has run on the Pi yet: where a step rests on something not yet confirmed, it says so.

Placeholders: `<user>` is the Linux user you create in the imager. The Pi's hostname is `pipeline-pi`.
Never paste a token, password or hotspot name into this repo or onto the classroom screen.

## 0. Flash the card (Mac)

Raspberry Pi Imager, device Raspberry Pi 400.

- OS: Raspberry Pi OS Lite (64-bit)
- Hostname `pipeline-pi`, your user, SSH on with your public key
- Wi-Fi: your phone hotspot (name and password go in the imager only)
- Timezone and keyboard set

Check: boot the Pi, then from the Mac

    ssh <user>@pipeline-pi.local uname -m

Expect: `aarch64`. If it fails on the hotspot, plug the cable (step 1).

## 1. Reach the Pi over the cable (no router)

Some hotspots stop devices seeing each other, so SSH must also work over the direct cable.

Check: Mac and Pi joined by Ethernet, Wi-Fi on the Mac switched off, then

    ssh <user>@pipeline-pi.local hostname

Expect: `pipeline-pi`. (It relies on the two machines giving themselves link-local addresses and finding
each other by name. Not yet confirmed on this hardware. If it fails, give both ends a fixed address.)

## 2. Clock at boot

The Pi 400 has no clock battery, so until it has network time, secure connections fail.

    sudo systemctl enable systemd-time-wait-sync.service
    timedatectl show -p NTPSynchronized

Expect: `NTPSynchronized=yes` once online. (Assumes Raspberry Pi OS uses systemd-timesyncd, not yet confirmed.)

## 3. Memory cgroup, then reboot

k3s needs it. Per the k3s docs, append `cgroup_memory=1 cgroup_enable=memory` to the one line in
`/boot/firmware/cmdline.txt`. It must stay on a single line.

    sudo cp /boot/firmware/cmdline.txt /boot/firmware/cmdline.txt.bak
    grep -q cgroup_memory /boot/firmware/cmdline.txt || sudo sed -i '1 s/$/ cgroup_memory=1 cgroup_enable=memory/' /boot/firmware/cmdline.txt
    wc -l /boot/firmware/cmdline.txt
    sudo reboot

Expect: `1 /boot/firmware/cmdline.txt` before the reboot. After it:

    grep -c memory /sys/fs/cgroup/cgroup.controllers

Expect: `1`.

## 4. Install k3s

Pinned to the version the demo was tested on. Traefik and ServiceLB are switched off: the tunnel goes
straight to the app, and it saves memory. The kubeconfig is made readable so `kubectl` works without sudo
on the classroom screen.

    sudo apt-get install -y git
    curl -sfL https://get.k3s.io -o /tmp/k3s-install.sh
    less /tmp/k3s-install.sh        # read it before running it
    sudo INSTALL_K3S_VERSION=v1.35.0+k3s1 INSTALL_K3S_EXEC="--disable=traefik --disable=servicelb --write-kubeconfig-mode=644" sh /tmp/k3s-install.sh
    echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc && . ~/.bashrc

Check:

    kubectl get nodes
    kubectl get pods -A

Expect: one node `Ready`, and only core pods (coredns, local-path, metrics-server) `Running`. If the node never
turns Ready, step 3 is the first suspect. `--write-kubeconfig-mode` is from memory, not confirmed in the docs:
if `kubectl` says permission denied, use `sudo chmod 644 /etc/rancher/k3s/k3s.yaml`.

## 5. Put the app on

    sudo git clone https://github.com/teerakarna/pipeline-demo /opt/pipeline-demo
    sudo mkdir -p /var/lib/pipeline-demo && sudo chmod 777 /var/lib/pipeline-demo
    sudo k3s crictl pull ghcr.io/teerakarna/pipeline-demo:v1

The pull needs the package to be public. If it says unauthorized, make the package public on GitHub.

    kubectl apply -f /opt/pipeline-demo/k8s/app.yaml
    kubectl rollout status deploy/pipeline-demo
    curl -s 'localhost:30080/api/status?cid=check'

Expect: three pods `1/1 Running`, and JSON with `"version":"v1"`. Check memory: `free -h` should leave well
over 1 GB available.

Reset token. It is made on the Mac, kept outside the repo, and handed to the cluster:

    # on the Mac, once
    mkdir -p ~/.config/pipeline-demo
    openssl rand -hex 16 > ~/.config/pipeline-demo/reset-token && chmod 600 ~/.config/pipeline-demo/reset-token
    ssh <user>@pipeline-pi.local "kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml create secret generic pipeline-demo --from-literal=reset-token=$(cat ~/.config/pipeline-demo/reset-token)"

    # on the Pi
    kubectl rollout restart deploy/pipeline-demo

Expect: `secret/pipeline-demo created`. The token is briefly visible in the command line, so do this before class.

## 6. The release loop

    sudo cp /opt/pipeline-demo/pi/release-loop.service /etc/systemd/system/
    sudo systemctl daemon-reload && sudo systemctl enable --now release-loop
    journalctl -fu release-loop

Expect: `watching https://github.com/teerakarna/pipeline-demo every 5s`, then `wanted v2, running v1: deploying`
and `v2 is live` (the manifest starts at v1, the loop moves it to the newest release). After that, nothing more
until the next release. Ctrl-C stops the log, not the loop. Not yet tested against GitHub itself, only
against a local stand-in: if you see git errors here, say so.

## 7. The tunnel (Cloudflare, you run these)

The placeholder Worker must be deleted first, because Cloudflare will not create a name over an existing
record:

    npx wrangler@4.158.0 login
    npx wrangler@4.158.0 delete
    npx wrangler@4.158.0 logout

(run from the placeholder's folder). Then in the Cloudflare dashboard, Networking, Tunnels:

1. Create a tunnel and name it. Choose Debian, arm64. Copy the install command it shows and run it on the Pi.
   The command contains a secret token: run it before class, never on the classroom screen, never in the repo.
2. Routes, Add route, Published application: subdomain `pipeline`, domain `kubernetic.io`,
   service URL `http://localhost:30080`.
3. Add only that one route. Touch no other record on the domain.

Not confirmed from the docs: whether adding the route creates the DNS record itself. Look in DNS afterwards
and check there is exactly one new `pipeline` record.

Check (from the Mac, on the hotspot, not the cable):

    curl -s 'https://pipeline.kubernetic.io/api/status?cid=check'

Expect: JSON with `"version":"v2"`, not `"placeholder"`.

## 8. Cold boot: no hands

    sudo reboot

Then touch nothing. After about 2 to 3 minutes, from the Mac:

    curl -s 'https://pipeline.kubernetic.io/api/status?cid=check'

Expect: the same JSON as step 7. Then check the pieces:

    systemctl is-active k3s release-loop cloudflared
    kubectl get pods

Expect: `active` three times and three pods `Running`. Write down how long it really took.

## Fallback images (do this before the talk)

If GitHub is slow or down, the Pi can run an image that was built on the Mac. Colima must be running, and the
Mac joined to the Pi by the cable. The version is the one the demo is about to show (the next after the newest release):

    scripts/fallback-load.sh v3 <user>@pipeline-pi.local

Expect: `built fallback-blue` and so on for each colour, then four `fallback-...` lines from the Pi's image list.
(`k3s ctr -n k8s.io images import` is from memory, not yet confirmed on the Pi: if the Pi's list is empty, say so.)

To use one on the day, on the Pi:

    cd /opt/pipeline-demo && pi/fallback-deploy.sh green

Expect: `fallback-green is live`. This stops the release loop, otherwise it would roll back to the newest release.
Afterwards, `sudo systemctl start release-loop` puts it back.

## Shutdown

Pulling the power can corrupt the card. Always:

    sudo shutdown -h now

Wait until the green light stops blinking, then unplug.

## The Pi terminal tab

So the class can tell Mac from Pi, give the Pi a red prompt:

    echo 'PS1="\[\e[1;41m\] PI \[\e[0m\] \w \$ "' >> ~/.bashrc && . ~/.bashrc

## When it goes wrong

| Symptom | First thing to check |
|---|---|
| Node never Ready | step 3: `grep -c memory /sys/fs/cgroup/cgroup.controllers` should print 1 |
| Image will not pull | package not public, or the clock is wrong (step 2) |
| Pods `ImagePullBackOff` after a release | the release's image is missing: the loop leaves the old copies serving |
| Pages show `placeholder` | the Worker is still bound to the name (step 7) |
| Page fine on the Mac, not on phones | the tunnel route or a network filter, test on mobile data |
| Nothing after a reboot | `systemctl status k3s release-loop cloudflared`, then `journalctl -u <name>` |
