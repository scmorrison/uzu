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

sub logger($message) is export {
    state $logger;
    $logger = Uzu::Logger::start() unless $logger;
    return &$logger($message);
}
