# 3.1 Dynamic Input via `execute_*.rb` Scripts

## Background

`wisco exec` currently uses JSON fixture files (`execute_*.json`) as input to connector items. This works well for stable, fixed inputs.

However, some scenarios require **dynamic input** — values that change between runs:

- **Create operations** that require a unique identifier per call (e.g. an order number that can't be reused)
- **Time-sensitive inputs** (timestamps, expiry dates) that should reflect "now" at execution time
- **Chained operations** where the input depends on an upstream lookup (e.g. fetching a real `customer_id` from a pick list before using it in an action)
- **Randomised test data** (e.g. fake names, emails, addresses for end-to-end testing)

This spec introduces support for Ruby script fixtures (`execute_*.rb`) that generate input dynamically.

---

## Overview

When `wisco exec` runs, it scans the item's fixture directory for both `execute_*.json` and `execute_*.rb` files:

- **`.json` files** behave as today — the file contents are the input.
- **`.rb` files** are eval'd; their last expression must return a Hash (for actions/triggers) or an Array (for methods/pick_lists). That return value becomes the input to the item.

Both types can coexist in the same fixture directory and **run independently**, producing separate output files.

---

## Discovery

In each item's fixture directory (e.g. `fixtures/actions/create_order/`), `wisco exec` collects every file matching:

- `execute_*.json` — JSON input fixtures (existing behaviour, unchanged)
- `execute_*.rb` — Ruby input fixtures (new)

Each file is processed as an independent run. The `--input=<file>` option can target a specific file (either `.json` or `.rb`); if omitted, all eligible files are run.

---

## Sentinel / Skip Behaviour

Mirroring the existing `.json` sentinel pattern, a `.rb` script is skipped if its **first non-blank line** is the comment:

```ruby
# WISCO_SKIP
```

This allows `wisco fixtures --ruby` to scaffold a template that the user must explicitly edit (remove the sentinel) before it will run.

---

## Script Contract

A valid `execute_*.rb` script is a Ruby file whose **last expression** evaluates to the input value:

- For **actions** and **triggers**: a `Hash`
- For **methods** and **pick_lists**: an `Array` (positional args) or `Hash` (named args)

```ruby
# fixtures/actions/create_order/execute_input.rb
require 'securerandom'

{
  customer_id: 12345,
  order_number: "ORD-#{SecureRandom.hex(4).upcase}",
  created_at: Time.now.iso8601,
  items: [
    { sku: 'WIDGET-001', quantity: 2 }
  ]
}
```

The script is evaluated inside a binding that mixes in the **helper module** (see §Helper Module). Any `require` calls and standard Ruby features are available.

### Invalid returns

If the script returns something other than a Hash/Array (e.g. `nil`, a String, an Integer), wisco treats it as a fixture failure and writes an `error.txt`.

---

## Helper Module

Before evaluation, wisco mixes in a helper module that provides three methods:

| Method | Returns | Purpose |
|---|---|---|
| `call_method(:name, *args)` | Whatever the method's lambda returns | Invoke a connector `methods:` entry by name. Useful for reusing connector helpers (e.g. `format_date`). |
| `call_pick_list(:name, *args)` | Array of `[label, value]` pairs | Invoke a connector `pick_lists:` entry. Useful for fetching real IDs at runtime (e.g. grab an existing `customer_id` to attach to a new order). |
| `connection` | `Hash` | The decrypted contents of `settings.yaml` (or `settings.yaml.enc`) for the connection name in `.wisco/config.json`. |

### `connection` — settings access

The `connection` helper reads the project's settings file using the same SDK loader path that `wisco exec` already uses to invoke the connector:

- Plain `settings.yaml` — read and parsed as YAML.
- Encrypted `settings.yaml.enc` — decrypted using `master.key` (Rails/`ActiveSupport::EncryptedConfiguration` convention, as Workato uses).

The connection name comes from `config.json` (`connection` key; defaults to `'default'`).

**Error handling:** If settings cannot be loaded (file missing, `master.key` missing, decryption fails, YAML parse error), `connection` returns `{}` and prints a single warning. The script continues. The reasoning: if settings are broken, the subsequent connector exec will fail with a clearer error anyway.

### Example using helpers

```ruby
# fixtures/actions/create_order/execute_input.rb
require 'securerandom'

# Grab a real customer ID from the connector's pick list
customers = call_pick_list(:active_customers)
customer_id = customers.first[1]   # [label, value]

# Build a formatted timestamp via a connector method
created_at = call_method(:format_timestamp, Time.now)

{
  customer_id:  customer_id,
  account_id:   connection[:account_id],
  order_number: "ORD-#{SecureRandom.hex(4).upcase}",
  created_at:   created_at
}
```

---

## Output Layout — Per-Script Subdirectory

To avoid cluttering the fixture directory and to keep `.rb` artefacts separate from `.json` artefacts, each `.rb` script's outputs live in a **subdirectory named after the script** (without the `.rb` extension).

### Example

For `fixtures/actions/create_order/execute_input.rb`:

```
fixtures/actions/create_order/
├── execute_input.json                  ← JSON fixture (existing)
├── execute_input.rb                    ← Ruby fixture (new)
├── input_fields.json
├── output_fields.json
├── output_execute_input.json           ← JSON run output (existing behaviour)
└── execute_input/                      ← .rb run subdirectory
    ├── input.json                      ← what the script generated this run
    ├── output.json                     ← exec result
    └── error.txt                       ← only present on failure
```

For multiple `.rb` scripts in one directory (e.g. `execute_basic.rb`, `execute_with_pricing.rb`), each gets its own subdirectory (`execute_basic/`, `execute_with_pricing/`).

### File contents

| File | When written | Contents |
|---|---|---|
| `input.json` | After the script returns a valid Hash/Array | The generated input, pretty-printed JSON. Lets the user see exactly what was sent. |
| `output.json` | After a successful exec call | The connector's response, pretty-printed JSON (same format as today's `output_execute_input.json`). |
| `error.txt` | When the script raises, returns invalid data, or the exec call fails | Error message + stack trace (same format as today's `error_*.txt`). |

---

## Cleanup Behaviour (applies to both `.json` and `.rb` runs)

The fixture directory should always reflect the **latest run only**. Stale files from previous runs are cleaned up:

| Run result | Cleanup |
|---|---|
| **Success** | Delete any prior `error.txt` (for `.rb`) or `error_<name>.txt` (for `.json`). Write the new `output.json` / `output_<name>.json`. |
| **Failure** | Delete any prior `output.json` (for `.rb`) and `input.json` (for `.rb`). Write the new `error.txt`. |

For `.json` runs (existing behaviour, now slightly refined):

| Run result | Cleanup |
|---|---|
| **Success** | Delete any prior `error_<name>.txt`. Write the new `output_<name>.json`. |
| **Failure** | Delete any prior `output_<name>.json`. Write the new `error_<name>.txt`. |

This is a small but meaningful UX fix — currently a stale `error_*.txt` could mislead the user into thinking the latest run failed.

---

## Error Handling

A `.rb` script run is treated as a **fixture failure** (the same category as a JSON exec failure) in any of these cases:

| Failure mode | `error.txt` contents |
|---|---|
| Script raises during evaluation | The exception class, message, and stack trace |
| Script returns a non-Hash/Array value | `Script must return a Hash (for actions/triggers) or Array/Hash (for methods/pick_lists). Got: <class>` |
| Script returns `nil` | Same as above |
| Connector exec call fails (after valid input was generated) | Standard exec exception trace (same as today) |

Failures do **not** abort a multi-item run — other items continue, mirroring the current JSON behaviour.

---

## Template Generation — `wisco fixtures --ruby`

A new flag is added to `wisco fixtures`:

```
wisco fixtures <path> [--ruby]
```

When `--ruby` is passed, in addition to the existing JSON template, wisco generates an `execute_input.rb` template:

```ruby
# WISCO_SKIP
# Remove the WISCO_SKIP line above once this script is ready to run.
#
# The last expression in this file becomes the input to the item.
# Helper methods available:
#   call_method(:name, *args)      — invoke a connector methods: entry
#   call_pick_list(:name, *args)   — invoke a connector pick_lists: entry
#   connection                      — Hash of decrypted settings.yaml

{
  # TODO: fill in fields
}
```

The sentinel line prevents the script from running until the user has filled it in.

If `execute_input.rb` already exists, the user is prompted before overwriting (consistent with existing fixture file behaviour).

---

## CLI Changes Summary

| Command | Change |
|---|---|
| `wisco exec` | Now also scans for `execute_*.rb` files. No new flags — `--input=<file>` accepts either `.json` or `.rb` paths. |
| `wisco fixtures` | New `--ruby` flag scaffolds an `execute_input.rb` template. |

---

## Implementation Notes

### Script evaluation

- Use `Kernel#eval` with the script's file contents in a `Binding` from a host object that mixes in the helper module. Avoid `instance_eval` so that `require` and top-level constants behave as in a normal Ruby file.
- Pass the file path and line number to `eval` (`eval(src, binding, file_path, 1)`) so stack traces in `error.txt` point at the script.

### Helper module — `call_method` / `call_pick_list`

These methods invoke the connector via `Workato::Connector::Sdk::ExecCommand` (or a lower-level `Connector` API). The connector path, connection name, and settings/key paths come from the same sources `wisco exec` already uses.

### Helper module — `connection`

Use `Workato::Connector::Sdk::Settings` (or the equivalent SDK loader) to read settings transparently. This avoids re-implementing the master.key decryption.

If loading raises, catch the exception, print a single warning (e.g. `[WARN] Could not load settings — connection helper will return {}`), and memoise `{}` so repeated `connection` calls don't repeat the warning.

### Sentinel detection

For consistency with `.json` sentinel detection, look only at the **first non-blank line** of the file. If it matches the regex `/\A\s*#\s*WISCO_SKIP\b/`, skip the script.

### Output directory creation

Before writing `input.json` / `output.json` / `error.txt`, ensure the script's subdirectory exists (`FileUtils.mkdir_p`).

---

## Summary of New / Changed Files

| File | Change |
|---|---|
| `lib/wisco/commands/exec.rb` | Detect `.rb` files; eval scripts; apply cleanup logic |
| `lib/wisco/exec_script.rb` (new) | Helper module + script evaluator |
| `lib/wisco/commands/fixtures.rb` | Add `--ruby` flag; emit `execute_input.rb` template |
| `lib/wisco/assets/execute_input.rb.erb` (new) | Template content for the Ruby fixture |
| `doc-specs/wisco-3-exec.md` | Cross-reference to this spec |
| `README.md` | Note dynamic input support under `wisco exec` |
