# wrktr

<p align="center">
  <img src=".github/assets/logo.png" alt="wrktr" width="200">
</p>

`wrktr` treats git branches as persistent directories instead of transient checkout states. You switch contexts by changing directories — every branch you are working on has its own folder on disk and nothing is ever stashed or lost.

```
~/projects/myapp/
    .wrktr/                 ← bare git database
    main/                   ← main branch, always here
    feature%2Flogin/        ← feature/login, always here
    fix%2Fcrash/            ← fix/crash, always here
```

`cd` into a branch to work on it. Run builds, tests, and your editor in multiple branches simultaneously. `git checkout` is not used.

---

## Requirements

- macOS or Linux (Windows requires WSL)
- bash 3.2 or later (the macOS default is sufficient)
- git 2.22 or later (git 2.42+ required for `wrktr_init`)
- rsync (required only by `wrktr_init`)

---

## Install

```bash
git clone https://github.com/gentbot/wrktr.git
cd wrktr
./install.sh
```

`install.sh` copies the script into `~/.local/lib/wrktr/` and asks before adding a `source` line to your shell profile. Run it with `--yes` to add the line without being asked, or `--no-profile` to never touch the profile (it prints the line for you to add yourself). When it is not run in a terminal it leaves the profile alone.

Then open a new terminal, or reload your shell profile:

```bash
source ~/.zshrc    # zsh
source ~/.bash_profile    # bash on macOS
source ~/.bashrc   # bash on Linux
```

---

## Updating

```bash
cd wrktr
./update.sh
```

Then in any open terminal that has wrktr loaded:

```bash
wrktr_reload
```

`update.sh` pulls the latest changes and reinstalls. `wrktr_reload` picks up the new
version in the current shell without opening a new terminal.

---

## Getting started

Clone an existing repo into the wrktr structure:

```bash
wrktr_clone https://github.com/user/myapp.git
```

Create a session config and load it:

```bash
wrktr_generate myapp
wrktr_use myapp
```

Start working on a branch:

```bash
wrktr_add feature/login     # creates the branch, creates the directory, cd's in
wrktr_go main               # jump to the main worktree
wrktr_status                # see all active worktrees at a glance
wrktr_rebase                # fetch + rebase current branch onto latest main
wrktr_push                  # push current branch
wrktr_remove feature/login  # remove worktree when done
```

---

## Converting an existing clone

If you already have a normal `git clone`:

```bash
wrktr_adopt ~/projects/myapp
```

---

## Starting a new project locally

```bash
mkdir -p ~/projects/myapp/main
wrktr_init
wrktr_generate myapp
wrktr_use myapp
```

---

## Multiple projects

```bash
wrktr_list          # see all available session configs
wrktr_use omi       # load a different project
wrktr_current       # show what is loaded in this shell
```

Sessions are shell-scoped. Each terminal manages its own session independently.

---

## Help

```bash
wrktr_help                  # all commands
wrktr_help add              # documentation for one command
wrktr_add --help            # same, inline
```

---

## Full documentation

See [wrktr.md](docs/wrktr.md) for the complete reference: all commands, arguments, configuration, branch encoding, deletion safety, and environment variables.

---

## License

MIT — see [LICENSE](LICENSE).
