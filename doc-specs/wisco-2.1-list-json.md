# 2.1 Machine readable mode for list

wisco supports listing the connector details to machine readable formats: JSON and YAML.

The command is `wisco list all --format=<format>`. 

`--format` is one of: `json` or `yaml` (case insensitve)

It will output all details for the connector to an object format.
The intention is to be used for by wisco vscode extension.

The JSON file should contain details about the connector.

## Structure

The output will be similar to the connector SDK hash structure.
It will not contain any code lambdas.

## Example

The JSON and YAML versions will appear similarly. This example shows JSON.

```json
{
    "title": "Connector Title", 

    "connection": {
        "fields": [
            # all the fields 
        ]
    },

    "actions": [
        "action_01": {
            "title": "Action title",
            "subtitle": "Action subtitle",
        }
    ],

    "triggers": [
        "trigger_01": {
            "title": "Trigger title",
            "subtitle": "Trigger subtitle",
        }
    ],

    "methods": [
        "method_01",
        "method_02"
    ],

    "pick_lists": [
        "pick_list_01",
        "pick_list_02"
    ],
}
```


## Sections

### 1. `title`
As per the connector's `title` key

### 2. `connection`
Keys:

- `fields` as per the connector

- Do not include `authorization`

### 3. `actions`

For each action key (eg: `action_01`):

Include the keys:

- `title`
- `subtitle`

### 4. `triggers`

For each action key (eg: `trigger_01`):

Include the keys:

- `title`
- `subtitle`

### 5. `methods`

Array of method keys

### 6. `pick_lists`
Array of pick_list keys
