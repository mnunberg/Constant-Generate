package Constant::Generate;
use strict;
use warnings;
our $VERSION  = '0.04';

use Data::Dumper;

#these two functions produce reverse mapping, one for simple constants, and
#one for bitfields

sub _gen_bitfield_fn {
	no strict "refs";
	my ($name,$hashref) = @_;
	*{$name} = sub {
		my $flag = shift;
		join("|", grep { $flag & $hashref->{$_} } (keys %$hashref)) || "";
	};
}

sub _gen_plain_fn {
	no strict "refs";
	my ($name,$hashref) = @_;
	my %reversed = reverse(%$hashref);
	*{$name} = sub { 
		$reversed{$_[0]} || "";
	};
}

sub fqcls ($); #predeclare
sub _getopt; #predeclare

use constant {
	CONST_BITFLAG 	=> 1,
	CONST_SIMPLE	=> 2
};

sub import {
	my ($cls,$symspecs,%opts) = @_;
	#die "This module is useless without options" unless %opts;
	my $reqpkg = caller();
	
	local *fqcls = sub ($) { $reqpkg . "::" . shift };
	local *_getopt = sub {
		my $opt = shift;
		foreach ($opt, "-$opt") { return delete $opts{$_} if (exists $opts{$_}) }
	};
	
	#Determine if we are generating incremental integer or shift constants
	my $type = _getopt("type");
	if(!$type || $type =~ /int/i) {
		$type = CONST_SIMPLE;
	} else {
		if ($type =~ /bit/i) {
			$type = CONST_BITFLAG;
		} else {
			die "Unrecognized type $type";
		}
	}
	
	#Determine our tag for %EXPORT_TAGS and reverse mapping
	my $mapname = _getopt("mapname");
	my $export_tag = _getopt("tag");
	if((!$mapname) && $export_tag) {
		$mapname = $export_tag . "_to_str";
	}
	my $generator = $type == CONST_BITFLAG ? \&_gen_bitfield_fn : \&_gen_plain_fn;
	
	
	#Generate the values.
	my %symhash;
	#Initial value
	my $v = _getopt("start_at") || 0;
	#Is this value an actual number, or a left-shift factor
	my $v_get_and_incr = $type == CONST_BITFLAG ? sub { 1 << $v++ } :
		sub { $v++ };
	#This actually writes the constant to the symbol table
	my $makesub = sub {
		no strict "refs";
		my ($name,$value) = @_;
		*{fqcls($name)} = sub () { $value };
	};
	
	#Figure out what are names are
	if(ref $symspecs eq 'ARRAY') {
		#Auto-generated values
		foreach my $sym (@$symspecs) {
			$symhash{$sym} = $v_get_and_incr->();
		}
	} else {
		#Predefined (user-specified) values
		%symhash = %$symspecs;
	}
	
	#tie it all together
	while (my ($symname,$symval) = each %symhash) {
		$makesub->($symname, $symval);
	}
	
	
	#After we have determined values for all the symbols, we can establish our
	#reverse mappings, if so requested
	if($mapname) {
		$generator->(fqcls($mapname), \%symhash);
	}
	
	my $auto_export = _getopt("export");
	my $auto_export_ok = _getopt("export_ok");
	my $a_exok = $auto_export_ok;
	my $a_ex = $auto_export;
	my $h_etags = _getopt("export_tags");
	
	foreach (\$a_ex, \$a_exok, \$h_etags) {
		$$_ = ref $$_ ? $$_ : undef;
	}
	
	my @symlist = keys %symhash;
	push @symlist, $mapname if $mapname;
	
	#At this point, we will see how to inject stuff into [@%]EXPORT_?(?:OK|TAGS)
	{
		no strict 'refs';
		
		if($auto_export_ok &&
		   !defined ($a_exok ||= *{$reqpkg."::EXPORT_OK"}{ARRAY})) {
			die "Requested export_ok but \@EXPORT_OK not yet declared";
		} else {
			push @$a_exok, @symlist;
		}
		if($auto_export && !defined ($a_ex ||= *{$reqpkg."::EXPORT"}{ARRAY})) {
			die "Requested export but \@EXPORT is not yet declared";
		} else {
			push @$a_ex, @symlist;
		}
		
		if(($auto_export || $auto_export_ok) && $export_tag) {
			if(!defined ($h_etags ||= *{$reqpkg ."::EXPORT_TAGS"}{HASH}) ) {
				die "Requested export with tags, but \%EXPORT_TAGS is not yet declared";
			} else {
				$h_etags->{$export_tag} = [ @symlist ];
			}
		}
	}
	if(%opts) {
		die "Unknown keys " . join(",", keys %opts);
	}
}

__END__

=head1 NAME

Constant::Generate - Common tasks for symbolic constants

=head2 SYNOPSIS

Simplest use
	
	use Constant::Generate [qw(CONST_FOO CONST_BAR) ];
	printf("FOO=%d, BAR=%d\n", CONST_FOO, CONST_BAR);

Bitflags:

	use Constant::Generate qw(ANNOYING STRONG LAZY), type => 'bitflags';
	my $state = (ANNOYING|LAZY);
	$state & STRONG == 0;

With reverse mapping:

	use Constant::Generate
		[qw(CLIENT_IRSSI CLIENT_XCHAT CLIENT_PURPLE)],
		type => "bitflags",
		mapname => "client_type_to_str";
	
	my $client_type = CLIENT_IRSSI | CLIENT_PURPLE;
	
	print client_type_to_str($client_type); #prints 'CLIENT_IRSSI|CLIENT_PURPLE';
	
Generate reverse maps, but do not generate values. also, push to exporter

	#Must define @EXPORT_OK and tags beforehand
	
	our @EXPORT_OK;
	our %EXPORT_TAGS;
	
	use Constant::Generate {
		O_RDONLY => 00,
		O_WRONLY => 01,
		O_RDWR	 => 02,
		O_CREAT  => 0100
	}, tag => "openflags", "export_ok" => \@EXPORT_OK;
	
	my $oflags = O_RDWR|O_CREAT;
	print openflags_to_str($oflags); #prints 'O_RDWR|O_CREAT';

=head2 DESCRIPTION

C<Constant::Generate> provides useful utilities for handling, debugging, and
generating opaque, 'magic-cookie' type constants as well as value-significant
constants.

At its simplest interface, it will generate a simple enumeration of names passed
to it on import.

Read import options to use

=head2 USAGE

All options and configuration for this module are specified at import time.

The canonical usage of this module is
	
	use Constant::Generate $symspec, %options;
	
=head3 Symbol Specifications

This is passed as the first argument to C<import> and can exist as a reference
to either a hash or an array. In the case of an array reference, the array will
just contain symbol names whose values will be automatically assigned in order,
with the first symbol being C<0> and each subsequent symbol incrementing on
the value of the previous. The default starting value can be modified using the
C<start_at> option (see L</Options>).

If the symbol specification is a hashref, then keys are symbol names and values
are the symbol values, similar to what L<constant> uses.

By default, symbols are assumed to correlate to a single independent integer value,
and any reverse mapping performed will only ever map a symbol value to a single
symbol name.

For bitflags, it is possible to specify C<type => 'bitfield'> in the L</Options>
which will modify the auto-generation of the constants as well as provide
suitable output for reverse mapping functions.

=head3 Options

The second argument to the import function is a hash of options.

=over

=item C<type>

This specifies the type of constant used in the enumeration for the first
argument as well as the generation of reverse mapping functions.
Valid values are ones matching the regular expression C</bit/i> for
bitfield values, and ones matching C</int/i> for simple integer values.

If C<type> is not specified, it defaults to integer values.

=item C<start_at>

Only valid for auto-generated values. This specifies the starting value for the
first constant of the enumeration. If the enumeration is a bitfield, then the
value is a factor by which to left-shift 1, thus
	
	use Constant::Generate [qw(OPT_FOO OPT_BAR)], type => "bitfield";
	
	OPT_FOO == 1 << 0;
	OPT_BAR == 1 << 1;
	#are true
	
and so on.

For non-bitfield values, this is simply a counter:

	use Constant::Generate [qw(CONST_FOO CONST_BAR)], start_at => 42;
	
	CONST_FOO == 42;
	CONST_BAR == 43;


=item C<tag>

Specify a tag to use for the enumeration.

This tag is used to generate the reverse mapping function, and is also the key
under which symbols will be exported via C<%EXPORT_TAGS>.

=item C<mapname>

Specify the name of the reverse mapping function for the enumeration. If this is
omitted, it will default to the form

	$tag . "_to_str";
	
where C<$tag> is the L</tag> option passed. If neither are specified, then a
reverse mapping function will not be generated

=item C<export>, C<export_ok>, C<export_tags>

This group of options specifies the usage and modification of
C<@EXPORT>, C<@EXPORT_OK> and C<%EXPORT_TAGS> respectively,
which are used by L<Exporter>.

Values for these options should either be simple scalar booleans, or reference
objects corresponding to the appropriate variables.

If references are not used as values for these options, C<Constant::Generate>
will expect you to have defined these modules already, and otherwise die.

=back

=head3 EXPORTING

This module also allows you to define a 'constants' module of your own, from which
you can export constants to other files in your package. Figuring out the right
exporter parameters is quite hairy, and the export options can natually
be a bit tricky.

In order to succesfully export symbols made by this module, you must specify
either C<-export_ok> or C<-export> as hash options to C<import>. These correspond
to the like-named variables documented by L<Exporter>.

Additionally, export tags can be specified only if one of the C<export> flags is
set to true (again, following the behavior of C<Exporter>). The auto-export
feature is merely one of syntactical convenience, but these three forms are
effectively equivalent

Nicest way:

	use base qw(Exporter);
	our (@EXPORT, %EXPORT_TAGS);
	use Constant::Generate
		[qw(FOO BAR BAZ)],
		-export => 1,
		-tag => "some_constants"
	;
	
A bit more explicit:

	use base qw(Exporter);
	use Constant::Generate
		[qw(FOO BAR BAZ)],
		-export => \our @EXPORT,
		-export_tags => \our %EXPORT_TAGS,
		-tag => "some_constants",
		-mapname => "some_constants_to_str",
	;


Or DIY

	use base qw(Exporter);
	our @EXPORT;
	my @SYMS;
	BEGIN {
		@SYMS = qw(FOO BAR BAZ);
	}
	
	use Constant::Generate \@SYMS, -mapname => "some_constants_to_str";
	
	push @EXPORT, @SYMS, "some_constants_to_str";
	$EXPORT_TAGS{'some_constants'} = [@SYMS, "some_constants_to_str"];

etc.
