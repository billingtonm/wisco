# 4. Generating Fixture Templates

The command `wisco fixtures` fetches the input and output field schemas for connector actions and triggers, then generates fixture template files used by `wisco exec`.

This is a setup/scaffolding step that must be run before `wisco exec` can be used for a given action or trigger.

## 4.1 Command

`wisco fixtures <path> [target_dir] [--overwrite] [--debug]`

#### Parameters
| Parameter    | Required | Meaning |
|--------------|----------|---------|
| path         | Yes      | Specifies key(s) to generate fixtures for. See following table. |
| target_dir   | No       | Directory containing `.wisco.json`. Defaults to current directory. |
| --overwrite  | No       | Default = false. If `execute_input.json` already exists and has been edited by the user (sentinel removed), it will not be overwritten unless this flag is set. |
| --debug      | No       | Optional debugging. |

#### Other options for `path`:
| Path Structure       | Meaning | Example |
|----------------------|---------|---------|
| *section*.*key*      | Find *key* in *section* | `actions.get_users`
| *section*            | Repeat for all keys in *section* | `triggers`
| *key*                | Find the *key* in any section — error if multiple matches found | `get_users`

#### Valid values for `section`
`actions`, `triggers`, `pick_lists` (new in v0.2.0)

(possibly more in future)

#### Examples
```
wisco fixtures actions.get_user
wisco fixtures triggers.new_event
wisco fixtures actions
wisco fixtures actions --overwrite
```

## 4.2 Steps
(Assuming the `action` is called `action_01`)

0. Ensures the output directory `./fixtures/actions/action_01/` exists, creating it as needed.

1. If the item is from the section `actions, triggers`:

    1. Calls ExecCommand with:
        - `path` = `actions.action_01.input_fields`
        - `options.connector` = from the `.wisco.json` file (key: connector.path)
        - `options.connection` = from the `.wisco.json` file (key: connection)
        - `options.output` = `./fixtures/actions/action_01/input_fields.json`

    2. Evaluates `input_fields.json` to determine the structure of the input hash for the action/trigger. Writes a template to `./fixtures/actions/action_01/execute_input.json` that the user will fill in before running `wisco exec`. The file contains a sentinel comment at line 1 marking it as an unedited template. See **Sentinel behaviour** and **Schema evaluation** below.

    3. Calls ExecCommand again for `output_fields`:
        - `path` = `actions.action_01.output_fields`
        - `options.output` = `./fixtures/actions/action_01/output_fields.json`

2. If the item is from the section `pick_lists`, (eg: `my_picklist`)

    1. Ensures directory `./fixtures/pick_lists/my_picklist/` exists, creating if it doesn't. This is the `output_directory` for this picklist.

    2. `my_picklist` should be a lambda. If the lambda has <=1 parameters then end. (Parameter 1 will be the `connection` parameter which we don't need to worry about)

    3. Otherwise, if the lambda has >1 parameters, generate an `execute_input.json` for all but the first parameter (which is the `connection` parameter). Each parameter should be assumed to be as string.

3. Repeats steps 1–3 for other keys if a *section* was specified as `path`.

If any ExecCommand call fails (e.g. the connector has an error in its field definitions), a warning is printed and the step is skipped — remaining steps continue.

## 4.3 Sentinel behaviour

`execute_input.json` is prefixed with a sentinel comment:

```
# Remove this comment before updating. Files that include this line will be overwritten.
```

Overwrite rules for `execute_input.json`:
| File state | `--overwrite` | Result |
|------------|---------------|--------|
| Does not exist | either | Write template |
| Exists, sentinel present | either | Overwrite (still a template) |
| Exists, sentinel removed | false (default) | Skip (user-edited) |
| Exists, sentinel removed | true | Overwrite |

## 4.4 Schema evaluation

The `input_fields` and `output_fields` schemas use a JSON array to describe the data going in and out of actions and triggers. `wisco fixtures` converts this schema into a template hash written to `execute_input.json`.

### Sample schema
```json
[
  {
    "name": "correlation_id",
    "hint": "Unique correlation ID for tracking this request"
  },
  {
    "name": "constituent",
    "type": "object",
    "optional": false,
    "properties": [
      {
        "name": "id",
        "type": "integer",
        "optional": false,
        "hint": "Oho Constituent ID"
      }
    ]
  },
  {
    "name": "identifier",
    "optional": false,
    "hint": "Put in license number as seen on card"
  },
  {
    "name": "license_class",
    "optional": true,
    "hint": "Accepted values are 'Car'"
  },
  {
    "name": "expiry",
    "type": "date",
    "optional": false,
    "hint": "Accreditation expiry date"
  }
]
```

### Resulting `execute_input.json` template
```json
# Remove this comment before updating. Files that include this line will be overwritten.
{
  "correlation_id": "<string_value_optional>",
  "constituent": {
    "id": "<integer_value_required>"
  },
  "identifier": "<string_value_required>",
  "license_class": "<string_value_optional>",
  "expiry": "<date_value_required>"
}
```

Fields of type `object` expand into a nested hash using their `properties`. Fields of type `array` expand into a single-element array. All other types produce a `"<type_value_required|optional>"` placeholder string.
