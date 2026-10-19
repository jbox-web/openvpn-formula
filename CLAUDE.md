# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Context

User-owned hard fork (`github.com/jbox-web/openvpn-formula`, single remote
`origin`) of the saltstack-formulas OpenVPN formula. It does **not** follow the
usual `template-formula` layout (`package/config/service` subdirectories,
`osfamilymap.yaml`): the sections below describe its own.

## Commands

```bash
bundle install
bin/install-hooks                               # pre-commit + commitlint hooks

bin/kitchen list                                # default-{debian-13-3008-2,debian-13-3006-27,debian-11-3006-27}
bin/kitchen converge default-debian-13-3008-2
bin/kitchen verify   default-debian-13-3008-2
bin/kitchen test     default-debian-13-3008-2   # destroy + converge + verify + destroy
bin/kitchen login    default-debian-13-3008-2

pre-commit run --all-files                      # commitlint, rubocop, shellcheck, yamllint, salt-lint, rstcheck, rst-lint
```

`bin/kitchen` is a Bundler binstub: never `bundle exec kitchen`. rubocop and
yamllint run on the whole tree (`always_run`, `pass_filenames: false`). The images
are amd64 only, so locally on arm64 they run emulated; the CI
(`.github/workflows/ci.yml`, identical across the forks) runs pre-commit then one
`bin/kitchen test` job per instance. `kitchen.vagrant.yml` / `kitchen.windows.yml`
are upstream leftovers, not exercised.

## Architecture

### States (flat, under `openvpn/`)

- `openvpn` (`init.sls`) — `repo`, `install` (`openvpn_pkgs`), `adapters`
  (Windows TAP), `dhparams`, `service`. It does **not** include the config.
- `openvpn.config` — includes `openvpn` and `general_config` (user, group,
  `conf_dir` owned by `root` mode 750), then renders one config file per instance.
  This is the state the Kitchen suite applies (after `openvpn._mapdata`).
- `openvpn.hardening` — `extend:`s `openvpn_config_<type>_<name>` to inject cipher
  settings into the template context.
- `openvpn.ifconfig_pool_persist`, `openvpn.gui` (Windows registry),
  `openvpn.network_manager_networks` (NetworkManager connections instead of a
  service) are standalone.

### Instances come from the pillar, not from `mapdata`

`config.sls`, `service.sls`, `adapters.sls` and `dhparams.sls` iterate
`pillar.get('openvpn')` and act on the keys `server`, `client` and `peer`, each a
dict of `<name>: <options>`. State IDs derive from them
(`openvpn_config_<type>_<name>`, `openvpn_<name>_service`). Option keys use
underscores and map to OpenVPN directives in `openvpn/files/*.jinja`;
`common_opts.jinja` holds the directives shared by all types, `peer.jinja` is
`common_opts` + `server.jinja`. For every file option (`ca`, `cert`, `key`,
`secret`, `tls_crypt`/`tls_auth`, `crl_verify`, `askpass`, `auth_user_pass`) a
matching `<option>_content` pillar key makes `config.sls` deploy the file through
`contents_pillar`. `multipart_param()` (`macros.jinja`) takes the first word of a
multi-word value such as `tls_auth: "<path> 0"`.

`server.jinja` (hence `peer.jinja`) re-reads its `config` from the pillar instead
of using the `config` passed in the state context; `client.jinja` uses the
context.

### `map.jinja` — `libmapstack` variant

Platform defaults live in `openvpn/parameters/`, loaded by `libmapstack.jinja` /
`libmatchers.jinja` (documented in `docs/map.jinja.rst`). The source order is set
by `parameters/map_jinja.yaml`: `defaults.yaml` (+ `defaults.yaml.jinja`, which
computes `multi_services` from the `systemd` grain) ← `osarch` ← `os_family` ←
`os` ← `oscodename` ← `osfinger` ← pillar `openvpn:lookup` ← `id`. Only
`openvpn:lookup` is merged — the `openvpn:` pillar root is deliberately left out.
States import it as `{% from "openvpn/map.jinja" import mapdata as map %}`. No
TOFS: templates are referenced by literal `salt://openvpn/files/...` paths.

### Service model

With `multi_services` (true under systemd) each instance is its own unit. On
Debian `parameters/os_family/Debian.yaml` sets per-type `conf_dir` and `service`:
servers go to `/etc/openvpn/server/<name>.conf` run by `openvpn-server@<name>`,
clients to `/etc/openvpn/client/<name>.conf` run by `openvpn-client@<name>`, and
`service.sls` stops and disables the legacy `openvpn@<name>` unit. Without
`multi_services` a single `openvpn_service` is managed.

## Tests

- `test/salt/pillar/default.sls` — one `myserver1` and one `myclient1` in static-key
  p2p mode (sets `lookup.user/group: openvpn` and `external_repo_enabled`).
- `test/integration/default/controls/` — `_mapdata.rb` compares
  `/tmp/salt_mapdata_dump.yaml` with `files/_mapdata/<os>-<major>.yaml`; only
  `debian-11.yaml` and `debian-13.yaml` are exercised by the current platforms,
  the other dumps are upstream leftovers. Any change to `parameters/` or to the
  test pillar's `lookup` must be carried into both Debian dumps.
- `config_spec.rb` expects config files owned by `root:openvpn`, mode `0640`, under
  `/etc/openvpn/{server,client}/` on Debian.
