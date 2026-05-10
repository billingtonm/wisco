# Push a connector to Workato

When the user has completed a development cycle, they will be ready to 'push' (or upload) their connector to workato from their local version.

The `wisco push` command will upload files from the local working folder to workato.

The following connector assets are uploaded:
- The connector code (eg: `connector.rb`)
- `./logo.png`
- `./README.md`
- Version notes


## Command

`wisco push` will upload connector assets from the local working folder to the remote workato server.

### Pre-requisites

- The user should have connector assets to push to workato. *See above*. If these files are missing, wisco will stop the push

- A `hostname` and `api_token` should be configured. If they are not, wisco will prompt the user for them.


### Options
`wisco push` supports the following options

| Option      | Default | Meaning  |
|-------------|---------|----------|
| --title     | (nil)   | Optional;  If specified, then this is specifies the title of the connector. *See **Setting Title** section below for detail*
| --notes     | (nil)   | Optional; Set the version notes. If not specified, then the user will be prompted for them.
| --folder    | (nil)   | Optional; The ID of the folder in your Workato workspace where you plan to push the connector. By default, the connector is not pushed to a specific folder unless you add the `--folder` parameter and folder ID.
| --verbose   | true    | Passed to the `workato push` command to enable detailed logging
| --debug     | false   | Show logging steps

#### Example: Basic usage
`wisco push`

Causes wisco to:
1. Prompt the user for version notes
2. Search for a title in one of: `config.json`,the connector, or otherwise prompt. *See **Setting Title** section below for detail*.
3. wisco will upload the connector assets, and search for the 

#### Example: Providing version notes
`wisco push --notes="My new version"`


#### Example: Uploading with a title
`wisco push --title="My Custom Connector"`

wisco will upload the connector assets to the workato specifying "My Custom Connector" as the title.

## Setting Title
A workato connector has a top-level 'title' set in workato. It also has a `title` key in the connector code.

If the user wants specify a title, they may do so by passing `--title="My Custom Connector"` as an option to the `push` command.

If `--title` is not specified then wisco will choose one of these values to use, in order of preference:
1. From wisco's `config.json` file: the value `connector.title` (if it exists)
2. From within the connector code, via the top-level key: `title` (if it exists)
3. It will prompt the user for a value

If the user provides a value via the `--title` option, or they provided one via a prompt, wisco will store that value in the config.json, in key `connector.title`.


# Implementation

To implement this command, the Workato Connector SDK must be used. This sample code demostrates how to do this:

```ruby
require 'workato/cli/push_command'

options = {
  environment: 'www.workato.com',    # From wisco config.json: use key: workato_developer_api.hostname
  api_token: 'your_api_token_here',  # From wisco config.json: use key: workato_developer_api.api_token
  folder: 12345,                     # Only if argument --folder specified, otherwise omit
  connector: 'connector.rb',         # From wisco config.json: use key connector.file
  title: 'My Connector',             # Preferences: 1) From wisco config.json: key: connector.title 2) If not exists then from connector key `title`
  notes: 'Initial release',          # From --notes, otherwise from user input
  verbose: true                      # From argument --verbose (otherwise true)
}

command = Workato::CLI::PushCommand.new(options: options)
command.call
```

# Workato Permissions

This command relies on the `workato push` command. 

It requires the following permissions to be enabled.

This is done in the Workato Platform via: `Workspace Admin` > `API Clients` > `Client Roles`

A client role is required to have the following permissions enabled:

- Projects
    - Deployments & lifecycle
        - Recipe lifecycle management:
            - ✅ Get package details  `GET /api/packages/:id`
            - ✅ Download package `GET /api/packages/:id/download`
            - ✅ Export package `POST /api/packages/export/:id`
            - ✅ Import package `POST /api/packages/import/:id`

- Tools
    - Connector SDKs
        - Connector SDKs
            - ✅ List `GET /api/custom_connectors`
            - ✅ Update custom connector `PUT /api/custom_connectors/:id`
            - ✅ Create custom connector `POST /api/custom_connectors`
            - ✅ Search custom connectors `GET /api/custom_connectors/search`
        - SDK CLI
            - ✅ Generate Schema from CSV `POST /api/sdk/generate_schema/csv`
            - ✅ Generate Schema from JSON `POST /api/sdk/generate_schema/json`

- Admin
    - Workspace details
        - ✅ Get details `GET /api/users/me`

