package Net::Z3950::FOLIO::Config;

use 5.008000;
use strict;
use warnings;

use IO::File;
use Cpanel::JSON::XS qw(decode_json);


# Possible values of $missingAction
sub MISSING_ERROR { 0 }
sub MISSING_ALLOW { 1 }
sub MISSING_REPORT { 2 }


sub new {
    my $class = shift();
    my($cfgbase, @extras) = @_;

    my $cfg = compile_config($cfgbase, @extras);
    return bless $cfg, $class;
}


sub compile_config {
    my($cfgbase, @extras) = @_;

    my $cfg = compile_config_file($cfgbase, MISSING_ERROR);

    my $isFirst = 1;
    while (@extras) {
	my $extra = shift @extras;
	my $overlay = compile_config_file("$cfgbase.$extra", $isFirst ? MISSING_ALLOW : MISSING_REPORT);
	$isFirst = 0;
	merge_config($cfg, $overlay);
    }

    my $gqlfile = $cfg->{graphqlQuery}
        or die "$0: no GraphQL query file defined";

    my $path = $cfgbase;
    if ($path =~ /\//) {
	$path =~ s/(.*)?\/.*/$1/;
	$gqlfile = "$path/$gqlfile";
    }
    my $fh = new IO::File("<$gqlfile")
	or die "$0: can't open GraphQL query file '$gqlfile': $!";
    { local $/; $cfg->{graphql} = <$fh> };
    $fh->close();

    return $cfg;
}


sub compile_config_file {
    my($cfgname, $missingAction) = @_;

    my $fh = new IO::File("<$cfgname.json");
    if (!$fh) {
	if ($! == 2 && $missingAction == MISSING_ALLOW) {
	    return {};
	} elsif ($! == 2 && $missingAction == MISSING_REPORT) {
	    Net::Z3950::FOLIO::_throw(1, "filter not configured: $cfgname");
	}
	die "$0: can't open config file '$cfgname.json': $!"
    }

    my $json; { local $/; $json = <$fh> };
    $fh->close();

    my $cfg = decode_json($json);
    expand_variable_references($cfg);
    return $cfg;
}


sub expand_variable_references {
    my($obj) = @_;

    foreach my $key (sort keys %$obj) {
	$obj->{$key} = expand_single_variable_reference($key, $obj->{$key});
    }

    return $obj;
}

sub expand_single_variable_reference {
    my($key, $val) = @_;

    if (ref($val) eq 'HASH') {
	return expand_variable_references($val);
    } elsif (ref($val) eq 'ARRAY') {
	return [ map { expand_single_variable_reference($key, $_) } @$val ];
    } elsif (!ref($val)) {
	return expand_scalar_variable_reference($key, $val);
    } else {
	die "non-hash, non-array, non-scale configuration key '$key'";
    }
}

sub expand_scalar_variable_reference {
    my ($key, $val) = @_;

    my $orig = $val;
    while ($val =~ /(.*?)\$\{(.*?)}(.*)/) {
	my($pre, $inclusion, $post) = ($1, $2, $3);

	my($name, $default);
	if ($inclusion =~ /(.*?)-(.*)/) {
	    $name = $1;
	    $default = $2;
	} else {
	    $name = $inclusion;
	    $default = undef;
	}

	my $env = $ENV{$name} || $default;
	if (!defined $env) {
	    warn "environment variable '$2' not defined for '$key'";
	    $env = '';
	}
	$val = "$pre$env$post";
    }

    return $val;
}


sub merge_config {
    my($base, $overlay) = @_;

    my @known_keys = qw(okapi login indexMap);
    foreach my $key (@known_keys) {
	merge_hash($base->{$key}, $overlay->{$key}) if defined $overlay->{$key};
    }

    foreach my $key (sort keys %$overlay) {
	if (!grep { $key eq $_ } @known_keys) {
	    $base->{$key} = $overlay->{$key};
	}
    }
}


sub merge_hash {
    my($base, $overlay) = @_;

    foreach my $key (sort keys %$overlay) {
	$base->{$key} = $overlay->{$key};
    }
}

=head1 NAME

Net::Z3950::FOLIO::Config - configuration file for the FOLIO Z39.50 gateway

=head1 SYNOPSIS

  {
    "okapi": {
      "url": "https://folio-snapshot-okapi.dev.folio.org",
      "tenant": "${OKAPI_TENANT-indexdata}"
    },
    "login": {
      "username": "diku_admin",
      "password": "${OKAPI_PASSWORD}"
    },
    "indexMap": {
      "1": "author",
      "7": "identifiers/@value/@identifierTypeId=\"8261054f-be78-422d-bd51-4ed9f33c3422\"",
      "4": "title",
      "12": {
        "cql": "hrid",
        "relation": "==",
        "omitSortIndexModifiers": [ "missing", "case" ]
      },
      "21": "subject",
      "1016": "author,title,hrid,subject"
    },
    "graphqlQuery": "instances.graphql-query",
    "queryFilter": "source=marc",
    "chunkSize": 5,
    "fieldMap": {
      "title": "245$a",
      "author": "100$a"
    }
  }

=head1 DESCRIPTION

The FOLIO Z39.50 gateway C<z2folio> is configured by a single file,
named on the command-line, and expressed in JSON.  This file specifies
how to connect to FOLIO, how to log in, and how to translate its
instance records into MARC.

The structure of the file is pretty simple. There are several
top-level section, each described in its own section below, and each
of them an object with several keys that can exist in it.

If any string value contains sequences of the form C<${NAME}>, they
are each replaced by the values of the corresponding environment
variables C<$NAME>, providing a mechanism for injecting values into
the condfiguration. This is useful if, for example, it is necessary to
avoid embedding authentication secrets in the configuration file.

When substituting environment variables, the bash-like fallback syntax
C<${NAME-VALUE}> is recognised. This evaluates to the value of the
environment variable C<$NAME> when defined, falling back to the
constant value C<VALUE> otherwise. In this way, the configuration can
include default values which may be overridden with environment
variables.


=head2 C<okapi>

Contains three elements (two mandatory, one optional), all with string values:

=over 4

=item C<url>

The full URL to the Okapi server that provides the gateway to the
FOLIO installation.

=item C<graphqlUrl> (optional)

Usually, the main Okapi URL is used for all interaction with FOLIO:
logging in, searching, retrieving records, etc. When the optional
C<graphqlUrl> configuration entry is provided, it is used for GraphQL
queries only. This provides a way of "side-loading" mod-graphql, which
is useful in at least two situations: when the FOLIO snapshot services
are unavailable (since the production services do not presently
included mod-graphql); and when you need to run against a development
version of mod-graphql so you can make changes to its behaviour.

=item C<tenant>

The name of the tenant within that FOLIO installation whose inventory
model should be queried.

=back

=head2 C<login>

Contains two elements, both with string values:

=over 4

=item C<username>

The name of the user to log in as, unless overridden by authentication information in the Z39.50 init request.

=item C<password>

The corresponding password, unless overridden by authentication information in the Z39.50 init request.

=back

=head2 C<chunkSize>

An integer specifying how many records to fetch from FOLIO with each
search. This can be tweaked to tune performance. Setting it too low
will result in many requests with small numbers of records returned
each time; setting it too high will result in fetching and decoding
more records than are actually wanted.

=head2 C<indexMap>

Contains any number of elements. The keys are the numbers of BIB-1 use
attributes, and the corresponding values contain instructions about
the indexes in the FOLIO instance record to map those access-points
to. The key C<default> is special, and is used for terms where no BIB-1
use attribute is specified.

Each value may be either a string, in which case it is interpreted as
a CQL index to map to (see below for details), or an object. When the
object version is used, that object's C<cql> member contains the CQL
index mapping (see below), and any of the following additional members
may also be included:

=over 4

=item C<omitSortIndexModifiers>

A bug in FOLIO's CQL query interpreter means that for some indexes,
query translation will fail if a sort-specification is provided that
requests certain valid behaviours, e.g. a case-sensitive search on the
HRID index. To work around this until it's fixed, an index's
C<omitSortIndexModifiers> allows you to specify a list of the
index-modifier types that they do not support, so that the server can
omit those qualifiers when creating sort-specifications. The valid
index-modifier types are C<missing>, C<relation> and C<case>.

=item C<relation>

If specified, the value is the relation that should be used instead of
C<=> by default when searching in this index. This is useful mostly
for defaulting to the strict-equality relation C<==> for indexes whose
values are atomic, such as identifiers.

=back

Each C<cql> value (or string value when the object form is not used)
may be a comma-separated list of multiple CQL indexes to be queried.

Each CQL index specified as a value, or as one of the comma-separated
components of a value, may contain a forward slash. If it does, then
the part before the slash is used as the actual index name, and the
part after the slash as a CQL relation modifier. For example, if the
index map contains

  "999": "foo/bar=quux"

Then a search for C<@attr 1=9 thrick> will be translated to the CQL
query C<foo =/bar=quux thrick>.

=head2 C<graphqlQuery>

The name of a file, in the same directory as the main configuration
file, which contains the text of the GraphQL query to be used to
obtain the instance, holdings and item data pertaining to the records
identified by the CQL query.

=head2 C<queryFilter>

If specified, this is a CQL query which is automatically C<and>ed with
every query submitted by the client, so it acts as a filter allowing
through only records that satisfy it. This might be used, for example,
to specify C<source=marc> to limit search result to only to those
FOLIO instance records that were translated from MARC imports.

=head1 SEE ALSO

=over 4

=item The C<z2folio> script conveniently launches the server.

=item C<Net::Z3950::FOLIO> is the library that consumes this configuration.

=item The C<Net::Z3950::SimpleServer> handles the Z39.50 service.

=back

=head1 AUTHOR

Mike Taylor, E<lt>mike@indexdata.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2018 The Open Library Foundation

This software is distributed under the terms of the Apache License,
Version 2.0. See the file "LICENSE" for more information.

=cut

1;
