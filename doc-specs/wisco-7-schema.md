# Generate a schema

## Background
Part of connector development is to generate `object_definitions` for `input_fields` and `output_fields`.

The `object_definition` defines the schema for the objects used as input to actions and output from actions and triggers.

The Workato SDK CLI provides a tool that assists with generating a schema using a CSV or JSON file as the input. This simplifies the process of generating a definition.

## Improvements to Workato CLI

Workato SDK CLI has a [generate schema](https://docs.workato.com/en/developing-connectors/sdk/cli/reference/cli-commands#workato-generate-schema) command.

Wisco can improve upon it to it to make it more user-friendly.

### 1. Input type detection.
Workato SDK CLI requires user to specify input file using using `--json` or `--csv`. 

Wisco will simplify this by detecting whether the input file is of type JSON or CSV. (If neither, it will fail.)

### 2. Output format
Workato SDK CLI outputs the schema in JSON format. However, for connector development the schema should be defined as a ruby hash.
Wisco will output to a ruby hash by default.

### 3. Specifying Workato API variables

The Workato SDK CLI command requires the user to supply the workato API Token, and (via an environment variable) the WORKATO_BASE_URL.

Wisco knows these values as they are in its `config.json` file.  ie:
```json
  "workato_developer_api": {
    "hostname": "app.au.workato.com",
    "api_token": "<set on first push/pull>"
  }
```
In this example `WORKATO_BASE_URL` value will be `https://app.au.workato.com`

Wisco will supply these values to the Workato SDK CLI command. (If they are not specified, then the user should provide them. (In a similar fashion to how the other commands (eg: `pull` ) do this).

### 4. Only outputs to stdout
wisco will support writing to a file as an option.

## Command
The command to generate a schema will be:

```
wisco schema input_file.json [OPTIONS]
```

The schema definition is returned to stdout.

### Options

| Option    | Description |
|-|-|
`--col_sep` | The column separators in the CSV file provided. Default: comma. Possible values: comma, space, tab, colon, semicolon, pipe. (This option is supported by the )
`--format` | The schema output format. Options=[`ruby`,`json`]. Default is `ruby`: The output will be a ruby array of hashes.
`--ruby_options` | Options for when the output format is `ruby` (`--format=ruby`). <br/> Options: `single_line`,`multi_line`. <br> `single_line`: output keys for field are all on a single line. <br> `multi_line`: a field definition is output over multiple lines, with one key per line. <br> Default is `multi_line`.
`--save` | Writes output to a file. If no file is specified, it will use the input_file name an add '.schema' to it. <br> eg: If input is `input_file.json` then output file name is `input_file.schema.<ext>` where `<ext>` is based on the the `--format`. *See below*


#### Notes
1. `--col_sep` is a standard Workato option (however workato calls it `col-sep`)
2. `--format`: Workato CLI only supoports JSON being returned, so wisco will handle the json->ruby conversion. (see *JSON to Ruby conversion* below for further information)
3. `--save` if specified but with no file, then the output file name will be:

eg: input = `input_file.json`
| `--format` | extension | output file name |
|-|-|-|
|`ruby`| `.rb` | `input_file.schema.rb` |
|`json`| `.json` | `input_file.schema.json` |




#### Command examples
1. `wisco schema input_file.json`

Basic usage: a schema is generated for input_file.json and returned in `ruby` format.

2. `wisco schema input_file.json --format=json`

Generates a schema for the data in `input_file.json` and outputs in JSON format.

## JSON to Ruby conversion
When converting the output schema to ruby, follow these conventions:

- Use symbols for keys, not strings

- List the keys in a specific order: 

    - name, label, type, of, control_type, convert_input, convert_output

- The user can specify how the fields are output using the `--ruby_options` option.
    - `single_line`: output keys for field are all on a single line. (Array fields are listed per line)
    - `multi_line`: a field definition is output over multiple lines

Example:
### Single Line
Each field is listed on a single line
```ruby
[
    { name: 'string_field_01', label: 'Field 01', type: :string},
    { name: 'array_02', label: 'Array of fields', type: :array, of: :object, properties:
        [
            { name: 'string_in_array', label: 'String in array'},
            { name: 'integer_in_array', label: 'Integer in array'}
        ]
    }
]
```

### Multi line
Each key is listed on a single line. The field definition spans multiple lines.
```ruby
[
    { name: 'string_field_01', 
      label: 'Field 01', 
      type: :string},
    { name: 'array_02', 
      label: 'Array of fields', 
      type: :array, 
      of: :object, 
      properties:
        [
            { name: 'string_in_array', 
              label: 'String in array'},
            { name: 'integer_in_array', 
              label: 'Integer in array'}
        ]
    }
]
```

# Implementation

wisco should use the `Workato::CLI::SchemaCommand` to handle the inital schema generation (to JSON).

## Error handling
If the input file is a JSON array, Workato's Generate Schema API returns the exception `Invalid JSON document(document should correspond to an object)`.

This is because it expects the top-level to be an object.
eg: input as a top-level array:
```json
[
  {
    "id": "gid://shopify/Order/6570948558891",
  }
]
```


wisco will assist the user with this by:
1. automatically encapsulating the array into an object with key `input`. ie:
```json
{"input":
    [
        {
            "id": "gid://shopify/Order/6570948558891",
        }
    ]
}
```

2. Informing the user that the input was an array, so the 'input' root-level object was added
3. Submitting this new structure to the Workato API.

Note: wisco **should not** update the input file during this process.
