# RabbitMQ X-Featrues Exchange Type #

This plugin adds a __features exchange__ type to [RabbitMQ](http://www.rabbitmq.com). The exchange type is `x-features`. See question on SO: http://stackoverflow.com/q/40606942/1002036.

## Installing ##

Build from source:
```
make rabbitmq-components-mk
make dist
```
then copy compiled plugin from directory `plugins` into rabbit plugins directory (by default is `/usr/lib/rabbitmq/lib/rabbitmq_server-VERSION/plugins/`).

More details about plugin building see in RabbitMQ [Plugin Development Guide](https://www.rabbitmq.com/plugin-development.html).

## License ##

See LICENSE.

## Credits ##

Serge - sergeg.2kgroup@gmail.com
