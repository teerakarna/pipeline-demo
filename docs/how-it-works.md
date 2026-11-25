# How it works

A small web page, and the machinery that gets a change to it in front of real users within a couple of
minutes. This page explains the machinery, one step at a time.

## The idea

DevOps is a loop, not a line: plan, code, test, build, release, deploy, operate, monitor, and what you learn
feeds the next plan. The point of the loop is to make changes small, safe and fast, so that shipping is boring.

```
 plan --> code --> test --> build --> release --> deploy --> operate --> monitor
   ^                                                                       |
   +-----------------------------------------------------------------------+
```

This demo walks one real change through all of it.

## One change, start to finish

```
 your laptop          GitHub                                         the Raspberry Pi
 -----------          ------                                         ----------------
 edit + test   push   pull request: Test
 (development) ---->  merge to main:
                        Test -> Build image -> Staging tests -> [Approve] -> Release
                                                                               |
                                                                     new release tag
                                                                               |
                                                            release loop notices (every 5 s)
                                                            3 copies replaced one by one
                                                            page updates for everyone
```

### Development: on a laptop

- Edit the code. The button colour is one line, `BUTTON_COLOUR` in `app/main.py`.
- `make test` runs the tests in about a tenth of a second. `make run` shows the page locally.
- Work happens on a short-lived branch, then a pull request into `main`. There is only one long-lived branch.
  This is called trunk-based development.

### The pull request: a first gate

- GitHub runs `Test` on every pull request. `main` is protected: nothing merges unless that check is green.
- A failing test blocks the change before it can reach anyone. The demo keeps one such pull request open.

### Merge to main: the pipeline

The file is `.github/workflows/release.yml`. Each box in the graph is a job:

| Job | What it does | About |
|---|---|---|
| Test | Runs the tests again on the merged code | 10 s |
| Build and push image | Packages the app into a container image and stores it in GitHub's registry | 30 s |
| Staging tests | Starts that exact image and checks it from the outside: page, version, voting, bad input, protected reset | 20 s |
| Approve and release | A person presses Approve. The tested image is tagged with the next version, and a release is created | 15 s plus you |
| Verify production | Polls the public address until it shows the new version | waits for the deploy |

Why it is shaped like this:

- **Build once, promote the same thing.** The image that passed staging is the image that ships. It is
  re-labelled with a version number, not rebuilt. What was tested is what runs.
- **Staging** here is a short-lived copy of the real image running on the build machine. Nobody can visit it,
  but it is a real run of the real image.
- **Approve** is a human gate. Everything before it is automatic. This is continuous delivery: every merge is
  ready to ship and a person decides when. Remove the gate and it becomes continuous deployment.
- **Only some changes release.** A change to the app, the Dockerfile or the requirements starts a release.
  Documentation and scripts do not, because they do not change the image.

### Production: the Raspberry Pi

- The Pi runs a small Kubernetes cluster (k3s). Kubernetes keeps three copies of the app running and replaces
  them if one dies.
- **The Pi pulls, GitHub does not push.** A short script, `pi/release-loop.sh`, looks at the repository's
  release tags every 5 seconds. If the newest one is not what is running, it tells Kubernetes to switch. This
  is a control loop: compare what you want with what you have, act, repeat. Nothing outside needs a way in.
- **Rolling update.** Kubernetes starts a new copy, waits until it reports ready, then retires an old one, one
  at a time. It never drops below three working copies, so users should not see an error. The page checks for a new
  version every 2 seconds and reloads itself.
- **A bad release is not an outage.** If the new image cannot start, the old copies keep serving and the
  loop reports the failure.
- **State** (votes, counts) lives in a database file shared by all copies, so every copy shows the same
  numbers. The page shows which copy served you.

### Operate and monitor

- The page itself is the dashboard: version, which copy answered, how many people are connected.
- `kubectl get pods -w` shows the copies changing during a release.
- A real system would add metrics, alerts and logs gathered in one place. This demo shows the idea, not the
  full tooling.

## What this demo leaves out

Real pipelines are bigger. Honest differences:

- Real teams usually have a separate staging environment that people can visit, not only a throwaway one.
- They have more kinds of tests (integration, performance, security scans) and often several approvers.
- They watch production with alerts, and can roll back with one command or automatically.
- Many deploy by pushing to each environment. This demo pulls, which is the GitOps style that tools such as
  Argo CD and Flux use.

## Where to look in the repo

| Path | What it is |
|---|---|
| `app/main.py` | The whole app, in one readable file |
| `tests/` | The tests that run on every pull request |
| `staging/` | The checks that run against the built image |
| `Dockerfile` | How the image is made, ten lines |
| `.github/workflows/` | The pipeline, one file for pull requests and one for releases |
| `k8s/app.yaml` | What Kubernetes should run: three copies, rolling update, a readiness check |
| `pi/release-loop.sh` | The control loop on the Pi |
| `docs/pi-setup.md` | Setting the Pi up from scratch |

## Words

- **Image**: a packaged copy of the app and everything it needs. **Container**: an image running.
- **Registry**: where images are stored. **Tag**: a label on an image or a commit, such as `v2`.
- **Pipeline**: the automatic sequence of jobs. **CI** builds and tests, **CD** delivers or deploys.
- **Kubernetes**: software that keeps the right number of containers running. **Pod**: one running copy.
- **Rolling update**: replacing copies gradually so the service never stops.
