# 2.1 Machine readable mode for list

wisco supports listing the connector details to machine readable formats: JSON and YAML.

The command is `wisco list all --format=<format>`. 

`--format` is one of: `json` or `yaml` (case insensitve)

It will output all details for the connector to an object format.
The intention is to be used for by wisco vscode extension.

The JSON file should contain details about the connector.

## Structure

*Changed in 0.4.1*
The output will be a JSON/YAML representation of the connector hash **except** for the following:

- lambdas (unless in the `methods` or `pick_lists` or `object_definitions`): will be converted to show as `__is_lambda__`  as a string value

- lambdas in the `methods` or `pick_lists`: Each of these should will have parameter introspection performed upon them, with the result being a `parameters` array.

- labmdas in the `object_definitions`. As these all *should* contain the same arguments, the detail is not necessary. The `object_definitions` section will just be an array of the `object_definitions` keys from the connector.

## Example

The JSON and YAML versions will appear similarly. This example shows JSON.

```json
{
    "title": "Connector Title", 

    "connection": {
        "fields": [
            # all the fields 
        ],

        "authorization": {
            # all the keys
            "type": "custom_auth", # example scalar
            "detect_on" : ["\"error\":\"invalid_token\""],
            "apply": "__is_lambda__" # denotes a lambda
        },

        "base_uri": "__is_lambda__"
    },

    "test": "__is_lambda__",

    "actions": {
        "action_01": {
            "title": "Action title",
            "subtitle": "Action subtitle",
            "description": "__is_lambda__"
        }
    },

    "triggers": {
        "trigger_01": {
            "title": "Trigger title",
            "subtitle": "Trigger subtitle",
            "help": "__is_lambda__"
        }
    },

    "methods": {
        "method_01": {
            "parameters": [
                ["<type_symbol>", "<name>"], # first parameter
                ["<type_symbol>", "<name>"], # second parameter
            ]
        },
        "method_02": {
            "parameters": [
                ["<type_symbol>", "<name>"], # first parameter
                ["<type_symbol>", "<name>"], # second parameter
            ]
        },
    },


    "pick_lists": {
        "pick_list_01": {
            "parameters": [
                ["<type_symbol>", "<name>"], # first parameter
                ["<type_symbol>", "<name>"], # second parameter
            ]
        },
        "pick_list_02": {
            "parameters": [
                ["<type_symbol>", "<name>"], # first parameter
                ["<type_symbol>", "<name>"], # second parameter
            ]
        },
    },

"object_definitions": [
        "obj_defn_01",
        "obj_defn_02"
    ]
}
```


## Sections

### 1. Root level values

#### title
As per the connector's `title` key

### 2. `connection`
Keys:

- `fields` as per the connector

### 2b. `test`
Included for completeness, but as per the the rule, will be shown as `__is_lambda__`.

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

*Changed in 0.4.1*: 

Keys per method, each key being an object containing parameters to the method lambda.The method keys are sorted in alphabetical order.

### 6. `pick_lists`
*Changed in 0.4.1*: 
Keys per pick_list, each key being an object containing parameters to the method lambda. The pick_list keys are sorted in alphabetical order.

### 7. `object_definitions`
*Added in 0.4.1*
Array of object_definitions sorted in alphabetical order by the key.

### Within section keys: `parameters`
For sections with a parameters array, this value is the output of calling `.parameters` on the lambda: two-element arrays [*type_symbol*, *name*]

The `parameters` array will contain the values in the order they are present in the lambda.

- *type_symbol*: 
    - positional parameters: one of `req`, `opt`, `rest`, 
    - keyword parameters: one of `keyreq`, `key`, `keyrest`
    - `block`

- *name*: parameter name

scenario 1:
`lambda { |x, y, z='default'| ............. }`

scenario 2:
`lambda {|x:, y: z: 'default'|  ..........}`

| Type Symbol | Meaning |
|-|-|
|req | required positional (scenario 1: x, y)
|opt | optional positional with default (scenario 1: z='default')|
|rest | splat *args (collects remaining positionals)|
|keyreq | required keyword (scenario 2: x:, y:)|
|key | optional keyword with default (scenario 2: z: 'default')|
|keyrest | keyword splat **opts (collects remaining keywords)\
|block | block parameter &block\
