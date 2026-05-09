# Wisco
`wisco.rb` is a script that makes working with the Workato SDK CLI easier

# 1. Getting started

`wisco init`

Run this in the connector folder such as `C:\Users\mbill\OneDrive - innovationquotient.com.au\Documents\Workato Connectors\Oho`

The script will attempt to locate the Connector module.
It will do so by:

1. Looking for `connector.rb`
2. Looking for another `*.rb ` files

It will test the candidate file by using `eval` on the file.
A valid connector yield a single hash, that contains a `title` key.

If no valid file is found, an error will be raised.

Otherwise a `.wisco.json` will be created in the root of the working folder.

Initially, it will contain:
```
{
    "connector": {
        "path": "<working directory>"
        "file": "<connector file name, eg. connector.rb>"
    }
}
```
