
# Webhook Multiplexer

Take all requests and copy them to different URLs.

Can add custom headers or change the HTTP method.


## Usage

## Copy to one server
```shell
WEBHOOK_MULTIPLEXER_URLS="https://echo-api.3scale.net" rackup
```

## Copy to several servers
```shell
WEBHOOK_MULTIPLEXER_URLS="https://echo-api.3scale.net;http://echo-api.3scale.net" rackup
```


## Override method and headers
```shell
WEBHOOK_MULTIPLEXER_URLS="GET,https://echo-api.3scale.net,Authentication: Bearer somekey" rackup
```

## Override method and headers and use several servers
```shell
WEBHOOK_MULTIPLEXER_URLS="GET,https://echo-api.3scale.net,Authentication: Bearer somekey;POST,https://echo-api.3scale.net" rackup
```

## Heroku
```shell
 heroku config:set WEBHOOK_MULTIPLEXER_URLS="http://requestb.in/18igo571;PUT,http://requestb.in/18igo571"
 git push heroku master
 ```
