# NAME

Net::Z3950::FOLIO::Config - configuration file for the FOLIO Z39.50 gateway

# SYNOPSIS

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
      "queryFilter": "source=marc",
      "graphqlQuery": "instances.graphql-query",
      "chunkSize": 5
      "postProcessing": {
        "marc": {
          "008": { "op": "regsub", "pattern": "([13579])", "replacement": "[$1]", "flags": "g" },
          "245$a": [
            { "op": "stripDiacritics" },
            { "op": "regsub", "pattern": "[abc]", "replacement": "*", "flags": "g" }
          ]
        }
      }
    }

# DESCRIPTION

The FOLIO Z39.50 gateway `z2folio` is configured by a stacking set of
JSON files whose basename is specified on the command-line. These
files specify how to connect to FOLIO, how to log in, and how to
search.

The structure of each of these file is the same, and the mechanism by
which they are stacked is described below. The shared format is
simple. There are several top-level sections, each described in its own
section below, and each of them is an object with several keys that can
exist in it.

If any string value contains sequences of the form `${NAME}`, they
are each replaced by the values of the corresponding environment
variables `$NAME`, providing a mechanism for injecting values into
the configuration. This is useful if, for example, it is necessary to
avoid embedding authentication secrets in the configuration file.

When substituting environment variables, the bash-like fallback syntax
`${NAME-VALUE}` is recognised. This evaluates to the value of the
environment variable `$NAME` when defined, falling back to the
constant value `VALUE` otherwise. In this way, the configuration can
include default values which may be overridden with environment
variables.

## `okapi`

Contains three elements (two mandatory, one optional), all with string values:

- `url`

    The full URL to the Okapi server that provides the gateway to the
    FOLIO installation.

- `graphqlUrl` (optional)

    Usually, the main Okapi URL is used for all interaction with FOLIO:
    logging in, searching, retrieving records, etc. When the optional
    `graphqlUrl` configuration entry is provided, it is used for GraphQL
    queries only. This provides a way of "side-loading" mod-graphql, which
    is useful in at least two situations: when the FOLIO snapshot services
    are unavailable (since the production services do not presently
    included mod-graphql); and when you need to run against a development
    version of mod-graphql so you can make changes to its behaviour.

- `tenant`

    The name of the tenant within that FOLIO installation whose inventory
    model should be queried.

## `login`

Contains two elements, both with string values:

- `username`

    The name of the user to log in as, unless overridden by authentication information in the Z39.50 init request.

- `password`

    The corresponding password, unless overridden by authentication information in the Z39.50 init request.

## `indexMap`

Contains any number of elements. The keys are the numbers of BIB-1 use
attributes, and the corresponding values contain instructions about
the indexes in the FOLIO instance record to map those access-points
to. The key `default` is special, and is used for terms where no BIB-1
use attribute is specified.

Each value may be either a string, in which case it is interpreted as
a CQL index to map to (see below for details), or an object. When the
object version is used, that object's `cql` member contains the CQL
index mapping (see below), and any of the following additional members
may also be included:

- `omitSortIndexModifiers`

    A bug in FOLIO's CQL query interpreter means that for some indexes,
    query translation will fail if a sort-specification is provided that
    requests certain valid behaviours, e.g. a case-sensitive search on the
    HRID index. To work around this until it's fixed, an index's
    `omitSortIndexModifiers` allows you to specify a list of the
    index-modifier types that they do not support, so that the server can
    omit those qualifiers when creating sort-specifications. The valid
    index-modifier types are `missing`, `relation` and `case`.

- `relation`

    If specified, the value is the relation that should be used instead of
    `=` by default when searching in this index. This is useful mostly
    for defaulting to the strict-equality relation `==` for indexes whose
    values are atomic, such as identifiers.

Each `cql` value (or string value when the object form is not used)
may be a comma-separated list of multiple CQL indexes to be queried.

Each CQL index specified as a value, or as one of the comma-separated
components of a value, may contain a forward slash. If it does, then
the part before the slash is used as the actual index name, and the
part after the slash as a CQL relation modifier. For example, if the
index map contains

    "999": "foo/bar=quux"

Then a search for `@attr 1=9 thrick` will be translated to the CQL
query `foo =/bar=quux thrick`.

## `queryFilter`

If specified, this is a CQL query which is automatically `and`ed with
every query submitted by the client, so it acts as a filter allowing
through only records that satisfy it. This might be used, for example,
to specify `source=marc` to limit search result to only to those
FOLIO instance records that were translated from MARC imports.

## `graphqlQuery`

The name of a file, in the same directory as the main configuration
file, which contains the text of the GraphQL query to be used to
obtain the instance, holdings and item data pertaining to the records
identified by the CQL query.

## `chunkSize`

An integer specifying how many records to fetch from FOLIO with each
search. This can be tweaked to tune performance. Setting it too low
will result in many requests with small numbers of records returned
each time; setting it too high will result in fetching and decoding
more records than are actually wanted.

## `postProcessing`

Specifies sets of transformations to be applied to the values of
fields retrieved from the back-end. At present, the only supported key
is `marc`, which specifies transformations to be applied to MARC
records (either standalone or as part of OPAC records); in the future,
post-processing for JSON and XML records may also be supported.

Within the `marc` sections, keys are the names of simple MARC fields,
such as `008`; or of complex field$subfield combinations, such as
`245$a`. The corresponding values specify the transformations that
should be applied to the values of these fields and subfields.

Transformations are represented by objects with an `op` key whose
values specifies the required operation. Either single transformation
or an array of transformations may be provided.

The following transformation operations are supported:

- `stripDiacritics`

    All diacritics are stripped from the value in the relevant field: for
    example, `délétère` becomes `deletere`.

- `regsub`

    A regular expression substitution is performed on the value in the
    relevant field, as specified by the parameters in the transformation
    object:

    - `pattern`

        A regular expression intended to matching some part of the field
        value. This is Perl regular expression, as overviewed in
        [perlretut](https://perldoc.perl.org/perlretut)
        and fully documented in
        [perlre](https://perldoc.perl.org/perlre)
        and as such supports advanced facilities such as back-references.

    - `replacement`

        The string with which to replace the part of the field value that
        matches the pattern. This may include numbered references `$1`,
        `$2`, etc., to parenthesized sub-expressions in the pattern. (If this
        statement means nothing to you, you need to
        [go and read about regular expressions](https://perldoc.perl.org/perlretut).)

    - `flags`

        Optionally, a set of flags such as `g` for global replacement, `i`
        for case-insensitivity, etc. See
        [Using regular expressions in Perl](https://perldoc.perl.org/perlretut#Using-regular-expressions-in-Perl).

For example, the MARC post-processing directive

      "245$a": [
        { "op": "stripDiacritics" },
        { "op": "regsub", "pattern": "[abc]", "replacement": "*", "flags": "g" }
      ]

Says first to remove all diacritics from the `245$a` (title) field of
the MARC record (so that for example `é` becomes `e`), then to
replace all vowels with asterisks.

# CONFIGURATION STACKING

To implement both multi-tenancy and per-database output tweaks that may be required for specific Z39.50 client application, it is necessary to allow flexibility in the configuration of the server, based both on Z39.50 database name and on further specifications. Three levels of configuration are therefore supported.

1. A base configuration file is always used, and will typically provide the bulk of the configuration that is the same for all supported databases. Its base name is specified when the server is invoked -- for example, as the argument to the `-c` command-line option of `z2folio`: when the server is invoked as `z2folio -c etc/config` the base configuration file is found at `etc/config.json`.
2. The Z39.50 database name provided in a search is used as a name of a sub-configuration specific to that database. So for example, if a Z39.50 search request come in for the database `theo`, then the additional database-specific configuration file `etc/config.theo.json` is also consulted. Often this file will specify the FOLIO tenant to be used for this database.

    Values provided in a database-specific configuration are added to those of the base configuration, overriding the base values when the same item is provided at both levels.

3. One or more _filters_ may also be used to specify additional configuration. These are specified as part of the Z39.50 database name, separated from the main part of the name by pipe characters (`|`). For example, if the database name `theo|foo|bar` is used, then two additional filter-specific configuration files are also read, `etc/config.foo.json` and `etc/config.bar.json`. The values of filter-specific configurations override those of the base or database-specific configuration, and those of later filters override those of earlier filters.

In the example used here, then, a server launched with `z2folio -c etc/config` and serving a search against the Z39.50 database `theo|foo|bar` will consult four configuration files:
`etc/config.json`,
`etc/config.theo.json` (if present),
`etc/config.foo.json`
and
`etc/config.bar.json`.

This scheme allows us to handle several scenarios in a uniform way:

- Basic configuration all in one place
- Database-specific overrides, such as the FOLIO tenant and any customer-specific definition of ISBN searching (see issue ZF-24) in the database configuration, leaving the standard definition to apply to other tenants.
- Application-specific overrides, such as those needed by the ABLE client (see issue ZF-25), specified only in a filter that is not used except when explicitly requested.

# SEE ALSO

- The `z2folio` script conveniently launches the server.
- `Net::Z3950::FOLIO` is the library that consumes this configuration.
- The `Net::Z3950::SimpleServer` handles the Z39.50 service.

# AUTHOR

Mike Taylor, <mike@indexdata.com>

# COPYRIGHT AND LICENSE

Copyright (C) 2018 The Open Library Foundation

This software is distributed under the terms of the Apache License,
Version 2.0. See the file "LICENSE" for more information.
