#!/usr/bin/perl -w

use strict;
use lib $ENV{MT_HOME} ? "$ENV{MT_HOME}/lib" : 'lib';
use lib $ENV{MT_HOME} ? "$ENV{MT_HOME}/plugins/RequiresLogin/lib" : 'plugins/RequiresLogin/lib';

use MT::Bootstrap App => 'MT::App::RequiresLogin';