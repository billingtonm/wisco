# 2. List contents of a connector
A Workato connector is a hash that contains keys.

## 2.1 List the overview of the connector
The command `wisco list` will list all the top level keys in a connector, along with a count of the child elements [nn].

The output will be a tree structure, reflecting the structure of the hash
Sample output:
```
├── connection
│   ├── fields [nn]
|   ├── authorization
|   |   ├── type
|   |   ├── apply
|   |   └── ... other keys ...
|   └── base_uri
├── test
├── actions [3]
│   ├── action_01
│   ├── action_02
│   └── action_03
├── triggers [2]
│   ├── trigger_01
│   └── trigger_02
├── object_definitions [4]
│   ├── obj_def_01
│   ├── obj_def_02
│   ├── obj_def_03
│   └── obj_def_04
├── methods [1]
│   └── method_01
└── pick_lists [0]

```

## 2.2 Listing actions
The command `wisco list actions` will list details of the `actions` key of the hash.
Output to a markdown-style table to stdout
The title and subtitle are keys of each item with in a trigger section.
If a title doesn't exist, use the item name defined under the 'actions' key.



```
| Key       | Title    | Subtitle      | 
|-----------|----------|---------------| 
| action_01 | my title | my subtitle   |
```

### Parameters
| Parameter          | Meaning            | Notes |
|--------------------|--------------------|-------|
| `--sort=<field>`   | Sorts the rows by the column header field | `field` is one of: [key,title] |


## 2.3 Listing Triggers
The command `wisco list triggers` will list details of the `triggers` key of the hash.
Output to a markdown-style table to stdout
The title and subtitle should are keys of each item with in a trigger section.
If a title doesn't exist, use the item name defined under the 'triggers' key.


```
| Key       | Title    | Subtitle      | 
|-----------|----------|---------------| 
| action_01 | my title | my subtitle   |
```

### Parameters
| Parameter          | Meaning            | Notes |
|--------------------|--------------------|-------|
| `--sort=<field>`   | Sorts the rows by the column header field | `field` is one of: [key,title] |


## 2.4 Listing all
The command `wisco list all` will combine the outputs of the previous 3 commands into a single output. (If other list subcommands are added, they would also be included)
