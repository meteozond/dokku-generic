# Install dokku-generic without git

The standard install path is `dokku plugin:install <git-url>`, but Dokku also accepts a plain directory copied to `/var/lib/dokku/plugins/available/<name>/`. Useful for airgapped or read-only environments.

The plugin directory **must** be named `generic` (matches the `generic:*` command prefix).

## Option 1 — `dokku plugin:install file://`

If you can get the directory onto the Dokku host any way (scp, rsync, USB drive…), Dokku itself can install from a local path:

```bash
# on the Dokku host, with the source already at /tmp/dokku-generic:
dokku plugin:install file:///tmp/dokku-generic generic
```

This runs the same install pipeline as the git path: copy → chown → enable → install-dependencies.

## Option 2 — rsync (incremental, with excludes)

```bash
# from your local checkout:
rsync -avz \
  --exclude=tmp --exclude=.git --exclude=docs \
  --exclude=.github --exclude=.idea --exclude=.claude \
  ./ root@dokku-server:/var/lib/dokku/plugins/available/generic/

# on the Dokku host:
ssh root@dokku-server bash -c '
  chown -R dokku:dokku /var/lib/dokku/plugins/available/generic
  dokku plugin:enable generic
  dokku plugin:install-dependencies --core
'
```

`rsync` is the right choice when you want to **resume** an interrupted transfer or **update** an existing install (only changed files copied).

## Option 3 — `scp -r` (one-shot directory copy)

If you don't have rsync but want a single command:

```bash
# from inside the source directory (cd /path/to/dokku-generic-source):
scp -r . root@dokku-server:/var/lib/dokku/plugins/available/generic

# OR by passing the source path explicitly:
scp -r /path/to/dokku-generic-source root@dokku-server:/var/lib/dokku/plugins/available/generic

# on the Dokku host:
ssh root@dokku-server bash -c '
  chown -R dokku:dokku /var/lib/dokku/plugins/available/generic
  dokku plugin:enable generic
  dokku plugin:install-dependencies --core
'
```

`scp -r` copies the whole directory but **has no `--exclude`** — you'll also transfer `.git/`, `tmp/`, IDE files, etc. Choose one of:

- **Clean tree first** (delete `.git/`, `tmp/`, `docs/` from a temporary copy).
- **Use `git archive` for a clean snapshot** (only files tracked by git, no `.git`):
  ```bash
  git archive HEAD | ssh root@dokku-server '
    mkdir -p /var/lib/dokku/plugins/available/generic &&
    tar -x -C /var/lib/dokku/plugins/available/generic
  '
  ```
- **Use `tar` with `--exclude` and pipe over ssh** (works without git):
  ```bash
  tar -cf - \
      --exclude=tmp --exclude=.git --exclude=docs \
      --exclude=.github --exclude=.idea --exclude=.claude \
      . | ssh root@dokku-server '
    mkdir -p /var/lib/dokku/plugins/available/generic &&
    tar -xf - -C /var/lib/dokku/plugins/available/generic
  '
  ```
- **Or just prune after `scp -r`:**
  ```bash
  ssh root@dokku-server 'rm -rf /var/lib/dokku/plugins/available/generic/{.git,tmp,docs,.github,.idea,.claude}'
  ```

- **Bash extglob to skip specific entries** (works in bash, may need `shopt -s extglob`):
  ```bash
  shopt -s extglob
  scp -r !(.git|tmp|docs|.idea|.claude) root@dokku-server:/var/lib/dokku/plugins/available/generic/
  ```

- **Zsh equivalent** (different glob syntax — uses `^` for negation, requires both `extended_glob` and `glob_dots` to also pick up needed dotfiles like `.actrc`):
  ```zsh
  setopt extended_glob glob_dots
  scp -r ^(.git|tmp|docs|.idea|.claude) root@dokku-server:/var/lib/dokku/plugins/available/generic/
  ```
  Or as a one-shot without changing shell options:
  ```zsh
  zsh -c 'setopt extended_glob glob_dots; scp -r ^(.git|tmp|docs|.idea|.claude) root@dokku-server:/var/lib/dokku/plugins/available/generic/'
  ```

Note: plain `scp -r ./*` also skips dotfiles, but that drops `.actrc`/`.editorconfig`/`.github/` which you usually want — the extglob/extended_glob forms exclude only the noise.

## Option 4 — tarball (compressed, single file)

```bash
# locally — package the plugin:
tar --exclude=tmp --exclude=.git --exclude=docs \
    --exclude=.github --exclude=.idea --exclude=.claude \
    -czf dokku-generic.tar.gz -C /path/to/dokku-generic .

# transfer to Dokku host any way (scp/curl/usb):
scp dokku-generic.tar.gz root@dokku-server:/tmp/

# on the Dokku host:
mkdir -p /var/lib/dokku/plugins/available/generic
tar -xzf /tmp/dokku-generic.tar.gz -C /var/lib/dokku/plugins/available/generic
chown -R dokku:dokku /var/lib/dokku/plugins/available/generic
dokku plugin:enable generic
dokku plugin:install-dependencies --core
```

## Option 5 — `docker cp` (Dokku running in Docker)

```bash
# Dokku is in a container called dokku:
docker cp /path/to/dokku-generic dokku:/var/lib/dokku/plugins/available/generic
docker exec dokku bash -c '
  chown -R dokku:dokku /var/lib/dokku/plugins/available/generic
  dokku plugin:enable generic
  dokku plugin:install-dependencies --core
'
```

## After copying files — REQUIRED init step

Whichever copy method you used, after files are in `/var/lib/dokku/plugins/available/generic/`, you MUST run the install script (creates `/var/lib/dokku/services/generic` with correct ownership and pulls ambassador/busybox images):

```bash
ssh root@dokku-server '
  chown -R dokku:dokku /var/lib/dokku/plugins/available/generic
  /var/lib/dokku/plugins/available/generic/install
  dokku plugin:enable generic
'
```

Equivalent via `dokku plugin:install-dependencies --core` (Dokku internally invokes our `install` script):

```bash
ssh root@dokku-server '
  chown -R dokku:dokku /var/lib/dokku/plugins/available/generic
  dokku plugin:enable generic
  dokku plugin:install-dependencies --core
'
```

If you skip this step, the first `dokku generic:create ...` will fail with:

```
mkdir: cannot create directory '/var/lib/dokku/services/generic': Permission denied
```

— because the dokku user can't write to `/var/lib/dokku/services/` (it belongs to root by default; only the install script (running as root) can create per-plugin subdirs and chown them to dokku).

## Verifying

After install, on the Dokku host:

```bash
dokku plugin:list | grep generic     # should be enabled
dokku generic:help                   # should print plugin help
dokku generic:list                   # should print "No generic services found"
```

## Removing

```bash
dokku plugin:disable generic
rm -rf /var/lib/dokku/plugins/available/generic
```

## Notes

- `chown -R dokku:dokku` is **required** — Dokku invokes plugin scripts as the `dokku` user; without correct ownership, lifecycle hooks (`pre-start`, `pre-delete`, ...) get permission errors.
- `dokku plugin:install-dependencies --core` runs our `install` script which creates `/var/lib/dokku/services/generic/` and pulls `dokku/ambassador` and `busybox` images. Skip on airgapped if you've pre-loaded those images via `docker load`.
- `dokku plugin:enable generic` creates a symlink in `/var/lib/dokku/plugins/enabled/`. Without it, the plugin is on disk but not active.
