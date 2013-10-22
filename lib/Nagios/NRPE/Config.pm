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

Nagios::NRPE::Config - Interface no NRPE config files

=head1 SYNOPSIS

use Nagios::NRPE::Config;

my $nrpe = Nagios::NRPE::Config->new({ 'config' => '/etc/nagios/nrpe.cfg' });

my $nrpe_pidfile = $nrpe->{'pid_file'};

my $check_load = $nrpe->{'command'}->{'check_load'};

=head1 DESCRIPTION

The B<Nagios::NRPE::Config> class implements an interface to the Nagios NRPE
config file, making it easy to examine the configuration to determine things
like command definitions.

=head1 AUTHOR

Jeremy Brinkley, E<lt>jbrinkley@proofpoint.comE<gt>

=cut

package Nagios::NRPE::Config;

use Carp;
use File::Spec;
use File::Basename;

use vars qw($me);

sub new {
   my ($class, $cfg) = @_;

   my $self = bless({}, $class);
   $self->{'_cfg'} = $cfg;
   if (defined($cfg->{'config'})) {
      $self->parse($cfg->{'config'});
   }

   return $self;
}

sub parse {
   my ($self, $file) = @_;

   $self->dbg("opening $file");
   if (open(my $fh, '<', $file)) {
      my $lno = 0;
      while (defined(my $line = <$fh>)) {
         $lno++;
         next if $line =~ /^\s*\#/;
         next if $line =~ /^\s*$/;
         chomp($line);
         $self->dbg("   considering $lno $line");
         my ($attr, $rest) = split(/ *= */, $line, 2);
         $self->dbg("   attr=$attr rest=$rest");
         if ($attr =~ /^command\[([^\]]+)\]/) {
            my $command = $1;
            $self->dbg("   found command definiton: $command");
            $self->{'command'}->{$command} = $rest;
            $attr = 'command';
         } elsif ($attr eq 'include') {
             $self->dbg("   found file to include: '$rest'");
             my $dir = dirname($file);
             my $includefile = File::Spec->rel2abs($rest, $dir);
             $self->parse($includefile);
         } elsif ($attr eq 'include_dir') {
             my $dir = dirname($file);
             my $includedir = File::Spec->rel2abs($rest, $dir);
             $self->parsedir($includedir);
         } else {
            $self->{$attr} = $rest;
         }
      }
   } else {
      croak("Could not open $file for parsing: $!");
   }
}

# I'm not sure if nrpe descends into "hidden" directories but I won't
# -jbrinkley/20120321
sub parsedir {
    my ($self, $dir) = @_;

    $self->dbg("parsedir('$dir')");

    $self->dbg("opening $dir");
    if (opendir(my $dirh, $dir)) {
        my @files = grep { $_ !~ /^\./ } readdir($dirh);
        for my $file (@files) {
            $self->dbg("   found entry '$file'");
            my $includeentry = File::Spec->join($dir, $file);
            if (-f $includeentry && $file =~ /\.cfg$/) {
                $self->dbg("   file ends in .cfg, parsing $includeentry");
                $self->parse($includeentry);
            } elsif (-d $includeentry) {
                $self->dbg("   file is subdirectory, parsing files within $includeentry");
                $self->parsedir($includeentry);
            } else {
            }
        }
        close($dirh);
    } else {
        $self->wrn("Couldn't open include directory $dir - $!");
    }
}

sub dbg {
   my ($self, @msg) =  @_;

   no warnings;

   if (defined($self->{'_cfg'}->{'debug'}) &&
       $self->{'_cfg'}->{'debug'} > 1) {
      print "DBG($me): ", join("\nDBG($me):    ", @msg), "\n";
      $self->log('debug', join(' ', @msg));
   }
}

sub log {
   my ($self, $pri, $msg) = @_;

   $self->{'_cfg'}->{'logger'}->($pri, $msg)
       if defined($self->{'_cfg'}->{'logger'});
}

sub wrn {
   my ($self, $msg) = @_;

   carp($msg);

   $self->log('warning', $msg);
}

1;
