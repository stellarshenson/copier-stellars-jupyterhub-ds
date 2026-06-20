# volumes-migrator

A terminal tool that copies Docker volumes from one name prefix to another. It
matches every volume named `{from_prefix}{tail}` and copies it to
`{to_prefix}{tail}`, preserving the tail (`_home`, `_workspace`, `_certs`, a
per-user suffix, anything that follows the prefix).

Like `certs-installer`, this is an operator-side helper that ships alongside the
copier template but is never rendered into a generated deployment. Run it from
the host that owns the Docker volumes.

## When you need it

A deployment's volumes are namespaced by `COMPOSE_PROJECT_NAME` (for example
`stellars-tech-ai-lab_hub_data`, `stellars-tech-ai-lab_hub_shared`), and per-user
lab homes carry their own prefix (`jupyterlab-<user>`). Whenever that prefix
changes you would otherwise lose access to the existing data:

- renaming the deployment (`COMPOSE_PROJECT_NAME` change) renames every
  `<old-project>_*` volume
- the v2.0 upgrade, where the upstream platform reworked its volume names

The migrator moves the data onto the new names so nothing is lost across the
rename. It copies rather than renames, so the originals stay in place until you
have verified the result.

## Usage

Run with no arguments for the interactive TUI (designer → plan → execution):

```bash
./extra/volumes-migrator/migrate_volumes.py
```

Or drive it entirely from the command line:

```bash
# preview the mapping without copying
./extra/volumes-migrator/migrate_volumes.py --from stellars-tech-ai-lab_ --to stellars-tech-ai-hub_ --dry-run

# copy, skipping the prompt
./extra/volumes-migrator/migrate_volumes.py --from stellars-tech-ai-lab_ --to stellars-tech-ai-hub_ --yes

# only the cert volumes, four parallel workers
./extra/volumes-migrator/migrate_volumes.py --from stellars-tech-ai-lab_ --to stellars-tech-ai-hub_ --filter '_certs$' --workers 4
```

## Options

- `--from PREFIX` source volume name prefix (e.g. `jupyterlab-`)
- `--to PREFIX` replacement destination prefix
- `--filter REGEX` regex applied to the full source volume name (empty = all matches)
- `--workers N` parallel copy containers (default 3)
- `--dry-run` mount both volumes and verify access, copy nothing
- `--overwrite` clean and replace a destination volume that already exists (default: error out and abort)
- `--remove-source` delete each source volume after its successful copy (default: keep sources)
- `--yes` skip the interactive plan and run from the CLI arguments

## How it works

- each copy runs `rsync -aAX --delete` inside a disposable `alpine` container - source mounted read-only, destination read-write; all metadata preserved
- destinations are never recreated - with `--overwrite` the existing volume is kept and its contents mirrored from the source (`--delete` clears stale files)
- sources are left intact by default; after the run the tool prints the `docker volume rm` commands for every volume it copied so you can clean up once verified
- the `--filter` regex matches the whole source name; note Docker encodes `.` in volume names as `-2e` (e.g. `alice.smith` appears as `alice-2esmith`)

## Requirements

- Docker (the tool shells out to `docker volume` and `docker run`)
- Python 3.10+ with `rich>=13` and `textual>=0.80`

The script carries an inline dependency block and a `uv run --script` shebang, so
the simplest invocation auto-installs its dependencies:

```bash
./extra/volumes-migrator/migrate_volumes.py
```

Without `uv`, install the dependencies once and run with any Python:

```bash
pip install rich textual
python extra/volumes-migrator/migrate_volumes.py --help
```
