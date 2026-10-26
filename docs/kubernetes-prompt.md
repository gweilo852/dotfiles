# Kubernetes prompt

The Starship `kubernetes` module shows the current context after the Git
status. Rules in `config/starship/starship.toml` shorten the name and colour
it by environment. The real context never changes; the rules affect only the
text in the prompt.

## Colours

| Environment | Tokens in the name | Colour |
| --- | --- | --- |
| Production | `prd`, `prod` (and `production` in other names) | red `#ed8796` |
| Staging | `stg`, `uat` (and `staging`) | yellow `#eed49f` |
| Testing | `tst`, `test`, `dev` | blue `#8aadf4` |
| Sandbox | `sandbox`, `sbx` | green `#a6da95` |
| Unknown | none of these | mauve `#c6a0f6` |

A token counts only as a whole, dash-separated word, so `proddata` is not
production.

## Naming conventions

### GKE

`gcloud container clusters get-credentials` creates contexts named
`gke_<project>_<location>_<cluster>`. The rules use the cluster name, not the
project, because one project can hold clusters for several environments.
They show the cluster name up to and including the environment token:

| Context | Display |
| --- | --- |
| `gke_<project>_europe-west4_deephaven-emea-prd-deephaven` | `deephaven-emea-prd` |
| `gke_<project>_europe-west4_cloudtools-global-prd-cloudtools` | `cloudtools-global-prd` |
| `gke_<project>_us-east4_cloudtools-us-tst-cloudtools` | `cloudtools-us-tst` |
| `gke_<project>_europe-west4_kafka-emea-tst-kafka` | `kafka-emea-tst` |
| `gke_<project>_europe-west4_defi-global-prd-defi-workloads` | `defi-global-prd` |
| `gke_<project>_europe-west4_runners-global-all-runners` | `runners-global-all-runners` (no token: full cluster name, mauve) |

A numbered variant of an environment keeps its number, so two production
clusters never share a name:

| Context | Display |
| --- | --- |
| `gke_<project>_europe-west4_deephaven-emea-prd-deephaven` | `deephaven-emea-prd` |
| `gke_<project>_europe-west4_deephaven-emea-prd-deephaven-prd2` | `deephaven-emea-prd2` |

The region stays in the name, so `cloudtools-us-prd` and
`cloudtools-global-prd` stay distinct.

### Keymaster

Keymaster contexts are named `keymaster.<domain>-<name>`. The rules drop the
domain and add a `km:` prefix, so they cannot be confused with a GKE cluster
of a similar name:

| Context | Display |
| --- | --- |
| `keymaster.<domain>-apac-kafka-prod` | `km:apac-kafka-prod` (red) |
| `keymaster.<domain>-apac-kafka-uat` | `km:apac-kafka-uat` (yellow) |
| `keymaster.<domain>-emea-cloudtools-tst` | `km:emea-cloudtools-tst` (blue) |

### Other contexts

Any other context (kind, minikube, EKS, a name you chose) is shown in full.
It is still coloured when its name contains an environment token, for
example `kind-dev` is blue.

## Adding a pattern

1. Add a `[[kubernetes.contexts]]` table to `config/starship/starship.toml`.
   Starship uses the **first** rule that matches, so put a specific rule
   above the general ones it overlaps:

   ```toml
   # EKS: show the cluster name from the ARN.
   [[kubernetes.contexts]]
   context_pattern = '^arn:aws:eks:[^:]+:[0-9]+:cluster/((?:.*-)?prd(?:-.*)?)$'
   context_alias = 'eks:$1'
   style = "bold red"
   ```

   - `context_pattern` is a Rust regular expression. It has no
     back-references. Anchor it with `^` and `$`.
   - `context_alias` can use capture groups as `$1`, `$2`.
   - `style` takes a palette colour: `red`, `yellow`, `blue`, `green`,
     `mauve`, `teal` and the other Catppuccin Macchiato names at the top of
     the file.

2. Add a row for each new case to `tests/k8s-contexts.tsv`
   (`context`, expected display, expected colour). Use fictitious project
   names and domains.

3. Run the test:

   ```sh
   tests/test-k8s-prompt.sh
   ```

   It builds a temporary kubeconfig for each case, runs
   `starship module kubernetes`, and checks the text and the colour. It also
   fails if two production rows have the same display name.

4. To check your real contexts without changing them:

   ```sh
   kubectl config get-contexts -o name
   starship module kubernetes   # the current context
   ```

Do not put employer names, internal domains or project IDs in the patterns.
Match the structure (`^gke_[^_]+_[^_]+_`, `^keymaster\.[a-z0-9.]+-`) instead.

## Hiding the module

The module is visible whenever a current context is set. To hide it on one
machine, copy the config, set `disabled = true` under `[kubernetes]` in the
copy, and point Starship at it from `~/.zshrc.local`:

```sh
export STARSHIP_CONFIG="$HOME/.config/starship-local.toml"
```
