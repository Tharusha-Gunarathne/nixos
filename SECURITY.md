# Publishing this configuration

Keep machine configuration in `.env.local`, copied from `.env.local.example`.
Keep private desktop launchers under `desktop_entries` and extra service ports
under `network.extra_tcp_ports` in that local file. Never add the local file to Git.
Local-only application details still exist in generated desktop files and the
Nix store on the machine; this protects the public repository, not against local
administrators.

Use the Git flake and read local configuration separately:

```sh
export NIXOS_LOCAL_CONFIG="$PWD/.env.local"
nix build --impure '.#nixosConfigurations.nixos.config.system.build.toplevel'
```

Never build this checkout with `path:.`: path flakes include ignored files.
Credentials are read from the local file at runtime. Protect it with mode `0600`.
Do not print its contents or include it in reports or support bundles.

Enable the repository checks after cloning:

```sh
git config core.hooksPath .githooks
git config filter.noctalia-settings.required true
python3 scripts/check-public-source.py
python3 scripts/check-public-source.py --history
```

The Noctalia Git clean filter is installed by Home Manager. Configure it before
staging live settings; a missing required filter must stop staging. Hooks and
pattern scanners are safeguards and cannot prove that all private data is absent.
Review the staged diff before every push. Public dependency URLs and project
owners are intentionally retained; they are needed to fetch the configuration.

Deleting a credential from Git does not revoke it. Rotate exposed credentials
with their providers. After a history rewrite, collaborators must re-clone or
carefully reset their copies; merging old history can reintroduce removed data.
Old clones, caches and hidden GitHub references may require separate cleanup.
