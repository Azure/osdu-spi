# Template Protection Check

Prevents initialization workflows from running in template development repositories.

## Usage

```yaml
jobs:
  check_template:
    runs-on: ubuntu-latest
    outputs:
      is_template: ${{ steps.check.outputs.is_template }}
    steps:
      - uses: actions/checkout@v5
      - name: Check repository type
        id: check
        uses: ./.github/local-actions/template-protection-check
        with:
          is_template_var: ${{ vars.IS_TEMPLATE }}
          github_is_template: ${{ github.event.repository.is_template }}

  initialize:
    needs: check_template
    if: needs.check_template.outputs.is_template == 'false'
    # ... initialization steps
```

## Behavior

- Checks `IS_TEMPLATE` repository variable (primary protection)
- Checks `github.event.repository.is_template` flag (secondary protection)
- Returns early with `is_template=true` if either check fails
- Outputs: `is_template` (true/false)

## Testing

```bash
cd .github/local-actions/template-protection-check
export IS_TEMPLATE="true"
export GITHUB_IS_TEMPLATE="false"
./action.sh  # Should output: is_template=true

export IS_TEMPLATE="false"
export GITHUB_IS_TEMPLATE="false"
./action.sh  # Should output: is_template=false
```