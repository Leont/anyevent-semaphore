package AnyEvent::Semaphore;

use 5.006;
use strict;
use warnings FATAL => 'all';

use AnyEvent;
use Carp 'croak';
use POSIX qw/mkfifo O_NONBLOCK O_RDONLY O_WRONLY/;

sub new {
	my ($class, %args) = @_;
	my $ret = bless { }, $class;
	if ($args{name}) {
		mkfifo($args{name}, $args{mode} || 0600) or croak "$args{name} is not a named pipe" if not -p $args{name};
		sysopen $ret->{in}, $args{name}, O_NONBLOCK|O_RDONLY or croak "Couldn't open named pipe $args{name} for reading: $!";
		sysopen $ret->{out}, $args{name}, O_NONBLOCK|O_WRONLY or croak "Couldn't open named pipe $args{name} for writing: $!";
	}
	else {
		pipe $ret->{in}, $ret->{out} or croak "Could";
		$ret->{$_}->blocking(0) for qw/in out/;
	}
	syswrite $ret->{out}, "\01" x (defined $args{initial_value} ? $args{initial_value} : 1);
	$ret->arm($args{callback}) if $args{callback};
	return $ret;
}

sub arm {
	my ($self, $callback) = @_;
	my $fh = $self->{in};
	$self->{handle} = AnyEvent->io(fh => $fh, poll => 'r', cb => sub { $callback->() if sysread $fh, my $buff, 1 });
	return;
}

sub disarm {
	my $self = shift;
	delete $self->{handle};
	return;
}

sub armed {
	my $self = shift;
	return defined $self->{handle}
}

sub post {
	my $self = shift;
	syswrite $self->{out}, "\01", 1;
	return;
}

1;

# ABSTRACT: Asynchronous semaphores for AnyEvent

__END__

=head1 SYNOPSIS

 use AnyEvent;
 use AnyEvent::Semaphore;
 
 my $cv = AnyEvent::CondVar->new;
 my $sem; $sem = AnyEvent::Semaphore->new(callback => sub {
     say "Waited semaphore in $$ at ", scalar localtime;
     sleep 1;
     $cv->send(0);
	 $sem->post;
 });
 fork or exit $cv->wait for 1..10;
 1 while wait > 0;

=head1 DESCRIPTION

This module implements asynchronous semaphores. This allows you to employ locking between processes without blocking your program.

This is not the same as what the Node.js community apparently calls an asynchronous semaphore, which is in fact a barrier instead of a semaphore. Semaphores are things that block when its value would become less than 0, barriers are things that block until they become zero. It's almost exactly the opposite.

=method new(%options)

This created a new asynchronous semaphore. It accepts named arguments.

=over 4

=item * callback

This sets the callback to be called when the semaphore is successfully decremented. If not given, the semaphore will not be armed during construction.

=item * initial_value

This sets the initial value of the semaphore. The default value is C<1>.

=item * name

Name of the pipe used to implement this. This must refer to a named pipe if existent, otherwise a new one will be created (deleting it is left for the user.

=item * mode

The permissions

=back

=method post()

Increment the semaphore by one, unlocking it.

=method arm($callback)

Arm the semaphore. It will set the C<$callback>, and activate a waiter with AnyEvent.

=method disarm

Disarm the semaphore. After this is called, it will no longer wait for the semaphore to become available.

=method armed

Checks if the semaphore is armed or not.
