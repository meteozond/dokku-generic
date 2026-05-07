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

## Option 2 — rsync

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

## Option 3 — tarball

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

## Option 4 — `docker cp` (Dokku running in Docker)

```bash
# Dokku is in a container called dokku:
docker cp /path/to/dokku-generic dokku:/var/lib/dokku/plugins/available/generic
docker exec dokku bash -c '
  chown -R dokku:dokku /var/lib/dokku/plugins/available/generic
  dokku plugin:enable generic
  dokku plugin:install-dependencies --core
'
```

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
