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
`actions`, `triggers`, `pick_lists`, `methods` (new in v0.2.2)

(possibly more in future)

#### Examples
```
wisco fixtures actions.get_user
wisco fixtures triggers.new_event
wisco fixtures actions
wisco fixtures pick_lists
wisco fixtures actions --overwrite
wisco fixtures methods
```

## 4.2 Steps

### Background Information: actions and triggers

Both actions and triggers have input and output fields. 
The `input_fields` lambda describes the schema of the data that is passed as input to the `execute` lambda (for actions) or `poll` lambda (for triggers).

Similarly, the `output_fields` lambda describes the schema of the data output by the `execute`/`poll` key.

actions and triggers can optionally have a `config_fields` key array. This describes meta-parameters that are used by the `input_fields` and `output_fields`.

### Processing Steps

(Assuming the `action` is called `action_01`)

0. Ensures the output directory `./fixtures/actions/action_01/` exists, creating it as needed.

1. If the item is from the section `actions` or `triggers`:

    1. If the `config_fields` array is not defined for this item, skip to step 4
    2. If `config_fields.json` exists (with no sentinel) then skip to step 4
    3. Create a `config_fields.json` for this item using the fields defined in the `config_fields` array. Warn the user that the config_fields file needs to be completed. Stop any furher processing for this item.
    4. Calls ExecCommand with:
        - `path` = `actions.action_01.input_fields`
        - `options.connector` = from the `.wisco.json` file (key: connector.path)
        - `options.connection` = from the `.wisco.json` file (key: connection)
        - `options.output` = `./fixtures/actions/action_01/input_fields.json`
        - `options.config_fields` = `./fixtures/actions/action_01/config_fields.json` (if detected at step 2)


    5. Evaluates `input_fields.json` to determine the structure of the input hash for the action/trigger. If `config_fields.json` exists, then the append/merge the fields in `config_fields.json` with those found in `input_fields.json`. Writes a template to `./fixtures/actions/action_01/execute_input.json` that the user will fill in before running `wisco exec`. The file contains a sentinel comment at line 1 marking it as an unedited template. See **Sentinel behaviour** and **Schema evaluation** below.

    6. Calls ExecCommand again for `output_fields`:
        - `path` = `actions.action_01.output_fields`
        - `options.output` = `./fixtures/actions/action_01/output_fields.json`
        - `options.config_fields` = `./fixtures/actions/action_01/config_fields.json` (if detected at step 2)

2. If the item is from the section `pick_lists`, (eg: `my_picklist`)

    1. Ensures directory `./fixtures/pick_lists/my_picklist/` exists, creating if it doesn't. This is the `output_directory` for this picklist.

    2. `my_picklist` should be a lambda. If the lambda has <=1 parameters then end. (Parameter 1 will be the `connection` parameter which we don't need to worry about)

    3. Otherwise, if the lambda has >1 parameters, generate an `execute_input.json` for all but the first parameter (which is the `connection` parameter). Each parameter should be assumed to be a string.

3. If the item is from the section `methods`, (eg: `my_method`)

    1. Ensures directory `./fixtures/methods/my_method/` exists, creating if it doesn't. This is the `output_directory` for this picklist.

    2. `my_method` should be a lambda. If the lambda has 0 parameters then end. (

    3. Otherwise, if the lambda has >=1 parameters, generate an `execute_input.json` for all parameters. Each parameter should be assumed to be a string. 

        - Note that for `methods` `execute_input.json` is an array of values which positionally relate to the parameters. *See below section* **4.5: Fixtures for methods**


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


## 4.4 Fixtures directory structure
The `fixtures` directory resides in the root of the connector.

It will contain files:

|Filename              | Meaning                |
|----------------------|------------------------|
| `execute_*.json`     | The parameters to be used to execute this item. `wisco fixtures ` creates `execute_input.json`, but any json file matching execute*.json will be executed by the `wisco exec` command. |
| `config_fields.json` | If an action or trigger has a `config_fields` key, this file will be created.
| `input_fields.json`  | The input fields definition for the item (if applicable) |
| `output_fields.json` | The output fields definition for the item (if applicable) |


```
├── fixtures
|   ├── actions
|   |   ├── action_01
|   |   |   ├── execute_input.json
|   |   |   ├── input_fields.json
|   |   |   └── output_fields.json
|   |   ├── action_01
|   |   ├── action_02
|   |   └── ... other actions ...
|   ├── methods
|   |   ├── methods_01
|   |   |   └── execute_input.json
|   |   └── ... other picklists ...
|   ├── picklists
|   |   ├── pick_list_01
|   |   |   └── execute_input.json
|   |   └── ... other picklists ...
|   └── triggers
|   |   ├── trigger_01
|   |   |   ├── execute_input.json
|   |   |   ├── input_fields.json
|   |   |   └── output_fields.json
```

## 4.5 Fixtures for methods
Note an example set of methods:
```ruby
methods: {
    get_customers: lambda do
      get('/api/v2/customers')
    end,

    sample_method: lambda do |string1, string2|
      string1 + ' ' + string2
    end,
  },
```

### get_customers
Has no parameters, so do not generate an `execute_input.json` file.

### sample_method
Has to parameters: `string1` and `string2`.

`execute_input.json` should contain:
```json
  [
    "string1",
    "string2"
  ]
```

