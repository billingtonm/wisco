# Workato Developer API

Workato's Developer API provides REST-style endpoints to the workato platform.

## Getting connected

### API Base URLs

The base URI of the API endpoints depends on the workato instance being connected to.

|Region|Base URI|
|------|--------|
|US Data Center|`https://www.workato.com/api/`|
|EU Data Center|`https://app.eu.workato.com/api/`|
|JP Data Center|`https://app.jp.workato.com/api/`|
|SG Data Center|`https://app.sg.workato.com/api/`|
|AU Data Center|`https://app.au.workato.com/api/`|
|IL Data Center|`https://app.il.workato.com/api/`|

API endpoints are all on `/api`, only the hostname varies.

#### Impact on wisco
The workato base hostname will need to be stored in the `.wisco.json` file that is created by the `wisco init` command. The file is created in the connector project directory the user is working in.

The user will need to supply the hostname.

### API Authorisation

The Workato Developer APIs use Bearer token in the request header.

```shell
curl  -X GET https://www.workato.com/api/users/me \
      -H 'Authorization: Bearer <api_token>'
```

#### Impact on wisco
The API token will need to be supplied by the user and stored in the `.wisco.json` file.

**Important:** The API token is considered to be sensitive data. The `.wisco.json` should already be in a `.gitignore` file. 

Could consider additionally encrypting it, using the `master.key` file that the workato sdk connector client does. (Although this introduces a dependency on that file already existing). The workato SDK creates this in the root of the connector folder when the user creates a new connector project.



## Connecting

wisco will need to fetch the hostname and API token before calling any API.

Suggested `.wisco.json` config:
```json
{
    ... # other keys

    # new key for the workato developer api configuration
    "workato_developer_api": {
        "hostname": "app.au.workato.com", # user to provide
        "api_token": "xxxxxxxxxxxxxxxxxx" # user to provide
    }
}

```

# Endpoint references

The following endpoints are available to be used.

## Search custom connector

The Search operation allows you to search for a custom connector in your workspace by title.

### Payload

| Name | Type | Description |
| --- | --- | --- |
| title | String _required_ | The case-sensitive title of the custom connector for which you plan to search. The search returns partial matches. |

### Sample request [​](https://docs.workato.com/en/workato-api/custom_connectors#sample-request-2)



```shell
curl -X GET https://<DC-SPECIFIC-API-BASE-URL>/api/custom_connectors/search \
  -H "Authorization: Bearer <API-CLIENT-TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "<connector_title>"
  }'
```

### Sample response

```json
{
    "id": 3066,
    "name": "new_connector_1_connector_4771_1626869114",
    "title": "Acme Connector",
    "logo": "<base_64 encoded logo>",
    "latest_version": 6,
    "latest_version_note": "Latest version",
    "latest_released_version": 4,
    "latest_released_version_note": null,
    "latest_shared_version": 6,
    "latest_shared_version_note": "Latest version",
    "oem_shared_version": 2,
    "oem_shared_at": "2024-02-02T08:05:22.047-07:00",
    "released_versions": [
        {
            "version": 4,
            "version_note": null,
            "created_at": "2022-08-11T07:24:58.890-07:00",
            "released_at": "2021-09-26T21:33:41.713-07:00"
        },
        {
            "version": 2,
            "version_note": "hello world",
            "created_at": "2024-02-08T05:05:34.136-07:00",
            "released_at": "2024-02-08T21:33:41.713-07:00"
        }
    ]
},
```

## Get custom connector code

The Get custom connector code operation allows you to fetch a custom connector's code.

```
GET /api/custom_connectors/:id/code
```

### URL parameters

| Name | Type | Description |
| --- | --- | --- |
| ID  | Integer _required_ | The ID of the custom connector for which you plan to fetch the code. You can find your custom connector ID in the search custom connector endpoint. |

### Sample request



```shell
curl -X GET https://<DC-SPECIFIC-API-BASE-URL>/api/custom_connectors/1/code \
  -H "Authorization: Bearer <API-CLIENT-TOKEN>"
```

### Sample response



```json
{
  "data": {
    "code": "<connector_code_stringified>"
  }
}
```