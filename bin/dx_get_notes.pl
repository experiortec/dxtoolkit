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
#
# Copyright (c) 2014,2019 by Delphix. All rights reserved.
#
# Program Name : dx_get_notes.pl
# Description  : Get database notes
# Author       : Paulo Maluf
# Created: 27 Sep 2022 (v1.0.0)


use strict;
use warnings;
use JSON;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev); #avoids conflicts with ex host and help
use File::Basename;
use Pod::Usage;
use FindBin;
use Data::Dumper;
use File::Spec;


my $abspath = $FindBin::Bin;

use lib '../lib';
use Databases;
use Engine;
use Timeflow_obj;
use Capacity_obj;
use Formater;
use Group_obj;
use Toolkit_helpers;
use Snapshot_obj;
use Hook_obj;
use MaskingJob_obj;
use OracleVDB_obj;

my $version = $Toolkit_helpers::version;

GetOptions(
  'help|?' => \(my $help),
  'd|engine=s' => \(my $dx_host),
  'name=s' => \(my $dbname),
  'format=s' => \(my $format),
  'type=s' => \(my $type),
  'envname=s' => \(my $envname),
  'group=s' => \(my $group),
  'rdbms=s' => \(my $rdbms),
  'primary' => \(my $primary),
  'host=s' => \(my $host),
  'instance=n' => \(my $instance),
  'instancename=s' => \(my $instancename),
  'dsource=s' => \(my $dsource),
  'debug:i' => \(my $debug),
  'config' => \(my $config),
  'save=s' => \(my $save),
  'olderthan=s' => \(my $creationtime),
  'dever=s' => \(my $dever),
  'all' => (\my $all),
  'version' => \(my $print_version),
  'nohead' => \(my $nohead),
  'configfile|c=s' => \(my $config_file)
) or pod2usage(-verbose => 1,  -input=>\*DATA);

pod2usage(-verbose => 2,  -input=>\*DATA) && exit if $help;
die  "$version\n" if $print_version;

my $engine_obj = new Engine ($dever, $debug);

$engine_obj->load_config($config_file);

if (defined($all) && defined($dx_host)) {
  print "Option all (-all) and engine (-d|engine) are mutually exclusive \n";
  pod2usage(-verbose => 1,  -input=>\*DATA);
  exit (1);
}

if (defined($instance) && defined($instancename)) {
  print "Filter -instance and -instancename are mutually exclusive \n";
  pod2usage(-verbose => 1,  -input=>\*DATA);
  exit (1);
}

Toolkit_helpers::check_filer_options (undef, $type, $group, $host, $dbname, $envname);

# this array will have all engines to go through (if -d is specified it will be only one engine)
my $engine_list = Toolkit_helpers::get_engine_list($all, $dx_host, $engine_obj);

my $output = new Formater();
my $dsource_output;

my $parentlast_head;
my $hostenv_head;

if (defined($rdbms)) {
  my %allowed_rdbms = (
    "oracle" => 1,
    "sybase" => 1,
    "mssql"  => 1,
    "db2"    => 1,
    "vFiles" => 1
  );

  if (! defined($allowed_rdbms{$rdbms})) {
   print "Option rdbms has a wrong argument - $rdbms\n";
   pod2usage(-verbose => 1,  -input=>\*DATA);
   exit (1);
  }

}

$output->addHeader(
      {'Appliance'      ,20},
      {'Database'       ,30},
      {'Group'          ,15},
      {'Type'            ,8},
      {'Notes'          ,100}
    );

my %save_state;

my $ret = 0;

for my $engine ( sort (@{$engine_list}) ) {
  # main loop for all work
  if ($engine_obj->dlpx_connect($engine)) {
    print "Can't connect to Dephix Engine $engine\n\n";
    $ret = $ret + 1;
    next;
  };

  # load objects for current engine
  my $databases = new Databases( $engine_obj, $debug);
  my $groups = new Group_obj($engine_obj, $debug);


  # filter implementation
  my $zulutime;
  if (defined($creationtime)) {
    $zulutime = Toolkit_helpers::convert_to_utc($creationtime, $engine_obj->getTimezone(), undef, 1);
  }
  my $db_list = Toolkit_helpers::get_dblist_from_filter($type, $group, $host, $dbname, $databases, $groups, $envname, $dsource, $primary, $instance, $instancename, $zulutime, $debug);
  if (! defined($db_list)) {
    print "There is no DB selected to process on $engine . Please check filter definitions. \n";
    $ret = $ret + 1;
    next;
  }

  my @db_display_list;

  if (defined($rdbms)) {
    for my $dbitem ( @{$db_list} ) {
      my $dbobj = $databases->getDB($dbitem);
      if ($dbobj->getDBType() ne $rdbms) {
        next;
      } else {
        push(@db_display_list, $dbitem);
      }
    }

    if (scalar(@db_display_list)<1) {
      print "There is no DB selected to process on $engine . Please check filter definitions. \n";
      $ret = $ret + 1;
      next;
    }

  } else {
    @db_display_list = @{$db_list};
  }

  for my $dbitem ( @db_display_list ) {
    my $dbobj = $databases->getDB($dbitem);
    my $groupname = $groups->getName($dbobj->getGroup());

    if (defined($dbobj->{description}) && $dbobj->{description} ne ''){
        $output->addLine(
          $engine,
          $dbobj->getName(),
          $groupname,
          $dbobj->getType(),
          $dbobj->{description}
        );
    }
    $save_state{$dbobj->getName()}{$dbobj->getHost()} = $dbobj->getEnabled();
  }
  
  if ( defined($save) ) {
      # save file format - userspecified.enginename
      my $save_file = $save . "." . $engine;
      open (my $save_stream, ">", $save_file) or die ("Can't open file $save_file for writting : $!" );
      print $save_stream to_json(\%save_state, {pretty => 1});
      close $save_stream;
    }
  
}
Toolkit_helpers::print_output($output, $format, $nohead);


exit $ret;

__DATA__

=head1 SYNOPSIS

 dx_get_notes     [-engine|d <delphix identifier> | -all ]
                  [-group group_name | -name db_name | -host host_name | -type dsource|vdb | -instancename instname | -olderthan date]
                  [-rdbms oracle|sybase|db2|mssql|vFiles ]
                  [-save]
                  [-config]
                  [-format csv|json ]
                  [-help|? ] [ -debug ]

=head1 DESCRIPTION

Get the notes from databases. 

=head1 ARGUMENTS

Delphix Engine selection - if not specified a default host(s) from dxtools.conf will be used.

=over 10

=item B<-engine|d>
Specify Delphix Engine name from dxtools.conf file

=item B<-all>
Display databases on all Delphix appliance

=item B<-configfile file>
Location of the configuration file.
A config file search order is as follow:
- configfile parameter
- DXTOOLKIT_CONF variable
- dxtools.conf from dxtoolkit location

=back

=head2 Filters

Filter databases using one of the following filters

=over 4