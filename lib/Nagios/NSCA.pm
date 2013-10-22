#!perl
# /* Copyright 2010 Proofpoint, Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# */

=head1 NAME

Nagios::NSCA - Interface to send_nsca command

=head1 SYNOPSIS

use Nagios::NSCA;

my $nsca = Nagios::NSCA->new({
    host => 'nagios',
    command => 'send_nsca',
    port => 5667,
    timeout => 60,
    config => '/etc/send_nsca.cfg' });

$nsca->add({ 'result' => 0, 'service' => 'ExampleService',
    'output' => 'ExampleService OK' });
$nsca->add({ 'host' => 'myhost', 'service' => 'ExampleService',
    'result' => 2, 'output' => 'ExampleService CRITICAL' });

$nsca->send;

=head1 DESCRIPTION

The Nagios::NSCA class implements an interface to the C<send_nsca>
command.

=head1 AUTHOR

Jeremy Brinkley, E<lt>jbrinkley@proofpoint.comE<gt>

=cut

package Nagios::NSCA;

use Sys::Hostname;
use Carp;
use Data::Dumper;

use vars qw($me);

BEGIN { $me = 'Nagios::NSCA' };

sub new {
   my ($class, $cfg) = @_;
   my $def = { 'command' => 'send_nsca', 'resolv' => '/etc/resolv.conf' };
   @{$def}{keys(%$cfg)} = values(%{$cfg});

   my $self = bless({ }, $class);
   $self->{'_cfg'} = $def;

   return $self;
}

# A simulation of Facter's domain-/fqdn-discovering logic
sub fqdn {
   my ($self) = @_;
   my $hostname = hostname();

   if ($hostname =~ /\./) {
      # We got it
      return $hostname;
   } else {
      # Need to find domainname
      my ($domain, $search);
      {  no warnings;
         $domain = `dnsdomainname`;
         chomp($domain);
      }
      if ($domain) {
         return $hostname . '.' . $domain;
      } else {
         if (open(my $fh, '<', $self->{'_cfg'}->{'resolv'})) {
            while (defined(my $line = <$fh>)) {
               if ($line =~ /domain\s+(\S+)/) {
                  $domain = $1;
               } elsif ($line =~ /search\s+(\S+)/) {
                  $search = $1;
               }
            }
            return $hostname . '.' . $domain if $domain;
            return $hostname . '.' . $search if $search;
         }
      }
   }
}
   

sub add {
   my ($self, $result) = @_;
   
   $result->{'host'} ||= $self->fqdn;

   push(@{$self->{'buffer'}}, $result);
}

sub send {
   my ($self) = @_;

   my @cmd = ($self->{'_cfg'}->{'command'});
   for my $pair (['-H', 'host'],
                 ['-p', 'port'],
                 ['-c', 'config'],
                 ['-to', 'timeout'],
                 ['-d', 'delimiter']) {
      my ($opt, $key) = @{$pair};
      push(@cmd, $opt, $self->{'_cfg'}->{$key})
          if $self->{'_cfg'}->{$key};
   }

   $self->dbg("send: command = " . join(' ', @cmd));

   my @results = map { $self->format_result($_) } @{$self->{'buffer'}};

   $self->dbg("send: results", @results);

   if (@{$self->{'buffer'}}) {
      if (my $pid = open(my $child, '|-')) {
         # parent
         # Not doing anything complicated like enforcing a timeout because
         # send_nsca has its own
         print $child join('', @results);
         close($child);   #close() waits for child and sets rv
         #waitpid($pid, 0);

         if ($? == -1) {
            croak("Couldn't execute because of: $!: " . join(' ', @cmd));
         } elsif ($? & 127) {
            croak("Command died with signal " . ($? & 127) . ": " .
                  join(' ', @cmd));
         } elsif ($? >> 8) {
            croak("Command exited with signal " . ($? >> 8) . ": " .
                  join(' ', @cmd));
         }
         $self->{'buffer'} = [ ];
      } else {
         # child
         exec(@cmd);
      }
   }
}

sub format_result {
   my ($self, $result) = @_;

   sprintf("%s\t%s\t%s\t%s\n", @{$result}{qw(host service result output)});
}

sub log {
   my ($self, $pri, $msg) = @_;

   $self->{'_cfg'}->{'logger'}->($pri, $msg)
       if defined($self->{'_cfg'}->{'logger'});

}

sub dbg {
   my ($self, @msg) = @_;

   if ($self->{'_cfg'}->{'debug'} > 1) {
      print "DBG($me): ", join("\nDBG($me):    ", @msg), "\n";
      $self->log('debug', join(' ', @msg));
   }
}

1;
