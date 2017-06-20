use v6;

unit module Uzu::Logger;

our sub start(
    Supplier $log = Supplier.new
    --> Block
) {
    start {
        react {
            whenever $log.Supply { say $_ }
        }
    }

    return -> $message, $l = $log {
        $l.emit: $message;
    }
}

