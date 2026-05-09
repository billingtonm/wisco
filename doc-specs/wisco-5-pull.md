# Pull a connector from Workato

The user may be wanting to work locally on a connector stored remotely in the workato platform.

The `wisco pull` command will download the remote connector to the users working directory.

It needs to use the Workato Developer APIs to do this. These are documented in `build-specs/workato-dev-api.md` file.

The following items can be retrieved by the Workato APIs:

- Connector Id (integer)
- Connector Name (internal name)
- Title (User facing name)
- Logo (stored in base64)
- Code
- Version History

## What is does
`wisco pull` will retrieve data from the Workato Developer API and store it locally.

All data will be stored in files underneath `./.wisco/pull/` (relative to Connectors working path (per the wisco config)). *If this location does not exist, create it.*

An exception here is for the `logo.png`.
It will be saved in the connector root **unless** there is already an existing logo.png there. To prevent it from being overwritten, the file will be instead saved in `.wisco/pull`


### Saving Data
#### API Payload
The response from the payload will be stored as a file with the filename of `meta.json`


#### Code
The `code` payload is the ruby source code of the remote connector.

Use the `name` key in the search API payload file as the filename for the code, with the `.rb` extension.
ie: `<name>.rb`

#### Logo
The logo is fetched via the `search` endpoint. It needs to be converted from base64.
It will be saved as `logo.png` in the root folder if a logo file does not already exist, otherwise it will be saved in the pull folder so as not to overwrite the existing logo.

#### Version History
The `search` endpoint's API response includes keys `latest*` and `recent_released_versions`.
Save these keys to: `versions.json`

## Command
`wisco pull` needs to support the following actions:

What to get:
`wisco pull --what=<value>,`

Mutliple values can be specified by separating with a comma (though doing so with `all` is redundant).

| What      | Meaning |
|-----------|---------|
| all       | (Default) Retrieve everything
| logo      | Retrieve the logo 
| code      | Retrieve the code
| versions  | Retrieve the version history
| meta      | The meta data just the API payload from the `search` endpoint. No other action is require for this, as the search endpoint response is already stored.

### Options

| Option      | Default | Meaning  |
|-------------|---------|----------|
| --title     | (nil)   | The title of the connector to search for. If not specified, attempt to derive it from the 'title' key in the working connector file. (ie: the one referred to in .`wisco.json`)
| --debug     | false   | Show logging steps


## Before Executing
This command requires connection details to the Workato API as specified in *Getting connected* in the `build-specs/workato-dev-api.md` file.

If those details are not set, raise a message to the user informing them that the details are required (in a helpful manner).

## Execution Flow

1. Unless the `--title` option was specified, derive the connector's `title` from the connector code.
2. Use `title` as the parameter to the `Search custom connector` endpoint. (save response)
3. If no data is found, or a 404 is returned, end with an error message.
4. If the user requested code (or all) via `--what` then call the `Get custom connector code` endpoint using the id from step 2's response. (save response)
5. Save the response data step 2 and 4, as specified in the *Saving Data* section above. Output each elements (code, logo, versions) file locations to the user.

