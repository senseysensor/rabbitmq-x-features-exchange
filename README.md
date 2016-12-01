# RabbitMQ X-Featrues Exchange Type #

This plugin adds a __features exchange__ type to [RabbitMQ](http://www.rabbitmq.com). The exchange type is `x-features`, much like [default rabbitMQ headers exchange](https://github.com/rabbitmq/rabbitmq-server/blob/master/src/rabbit_exchange_type_headers.erl) but with different behaviour. See [question on SO](http://stackoverflow.com/q/40606942/1002036).

Shortly: consumers when bind to exchange, list their _features_ as bind arguments (for instance, `f1=true`, `country=US`). Arguments starting with _x-_ are ignored (are not used for routing). Publisher should list required features to process the message in headers. At least one header is required. Like in bindings, headers starting with _x-_ are also ignored. In order message to be routed, ALL its headers (except those start with _x-_) should exactly match binding arguments. Given binding may have more arguments (available features) are not listed in message headers.

Additionally is available exchange argument `pick_random` which if is set to `true` will choose random binding if more than one binding fits conditions (otherwise if false or ommitted message will be routed to all bindings).

## Installing ##

Build from source:

    make rabbitmq-components-mk && make dist

then copy compiled plugin from directory `plugins` into rabbit plugins directory (by default is `/usr/lib/rabbitmq/lib/rabbitmq_server-VERSION/plugins/`).

More details about plugin building see in RabbitMQ [Plugin Development Guide](https://www.rabbitmq.com/plugin-development.html).

## Disclamer ##

I am not expert in erlang (this was my first experience with the plugin). I took sources from headers exchange and random exchange plugin and managed implement this one. Would be glad for help, critic and pull requests.

## License ##

See LICENSE.

## Credits ##

Serge - sergeg.2kgroup@gmail.com
