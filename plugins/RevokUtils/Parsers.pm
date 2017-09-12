############################################################
# RevokUtils::Parsers module for Openkore Plugins
#
# This program is free software; you can redistribute it and/or 
# modify it under the terms of the GNU General Public License 
# as published by the Free Software Foundation; either version 2 
# of the License, or (at your option) any later version.
#
# Copyright (c) 2005-2006 OpenKore Development Team and iMikeLance/Revok
############################################################
package RevokUtils::Parsers;

use strict;
use Exporter;
use base qw(Exporter);
use encoding 'utf8';
use Log qw( warning message error );
#use Regexp::Common qw /comment/;

our @EXPORT = (
	qw/parseGM_db parseSectionedFile isIn_StringList reWrite_StringList parseStringList_toArray parseConfigArray
	isIn_Array isIn_Array_Regex/,
);

sub parseGM_db {
	my ($file, $arrayref) = @_;
	open (FILE, "<:utf8", $file) or die;
		while (<FILE>) {
				chomp;
				$_ =~ s/\s+//; # remove all spaces
				$_ =~ s/\r?\n|\r//g; # remove linebreak
				if ($_ =~ /(\d+)/) { # parse only numbers
					push (@{$arrayref}, $_);
				}
		}
	close FILE;
	
	return 1;
	
	#warning("DB loaded with ".@{$arrayref}." IDs!.\n");
}

sub parseStringList_toArray {
	my ($file, $array_ref) = @_;
	open (FILE, "<:utf8", $file) or die;
		while (<FILE>) {
				chomp;
				$_ =~ s/^\s+//; #remove leading spaces
				$_ =~ s/\s+$//; #remove trailing spaces
				$_ =~ s/\r?\n|\r//g; # remove linebreak
				if (length($_)) { # ignore white lines
					push (@{$array_ref}, $_);
				}
		}
	close FILE;
	return 1;
}

sub reWrite_StringList {
	my ($file, $array_ref) = @_;
	open (FILE, ">:utf8", $file) or return 0;
	foreach (@{$array_ref}) {
		print FILE $_."\n";
	}
	close FILE;
	return 1;
}

sub isIn_StringList {
	my ($array_ref, $value) = @_;	
	foreach	(@{$array_ref}) {
		return 1 if ($value eq $_);
	}
	return 0;
}

sub isIn_Array {
	my ($arg, $array_ref) = @_;
	chomp ($arg);
	foreach (@{$array_ref}) {
		chomp ($_);
		if ($_ == $arg){
		#msg("Match at $_ with $arg");
		return 1;
		
		}
	}
	return 0;
}

sub isIn_Array_Regex {
	my ($arg, $array_ref, $i) = @_;
	chomp ($arg);
	foreach (@{$array_ref}) {
		my $line = $_;
		chomp ($line);
		if ($arg =~ /$line/ || ($i && $arg =~ /$line/i)) {
			return $line;
		}
		
	}
	return 0;
}

sub parseSectionedFile {
	my ($file, $hash_ref) = @_;
	#die;
	open (FILE, "<:utf8", $file) or die $!;
	#warning "$file FILE \n";
	my $current_section;
		while (<FILE>) {
				chomp;
				my $line = $_;
				#warning $line."\n";
				#$line =~ s/\s+//;
				$line =~ s/\#.*//; # remove comments
				$line =~ s/^\s+//; #remove leading spaces
				$line =~ s/\s+$//; #remove trailing spaces
				$line =~ s/\r?\n|\r//g; # remove linebreak
				next unless ($line); # skip empty lines
				next if /^\#/;
				next if /^$/;
				
				if ($line =~ /^!include (.*)/) {
					 use File::Basename;
					 my($filename, $directory, $suffix) = fileparse($file);
					open (FILEINCLUDED, "<:utf8", $directory.$1) or die "Invalid include $!";
					#Log::error "$directory$1 FILE \n";
					while (<FILEINCLUDED>) {
						chomp;
						my $linei = $_;
						
						#$line =~ s/\s+//;
						$linei =~ s/\#.*//; # remove comments
						$linei =~ s/^\s+//; #remove leading spaces
						$linei =~ s/\s+$//; #remove trailing spaces
						$linei =~ s/\r?\n|\r//g; # remove linebreak
						next unless ($linei); # skip empty lines
						next if /^\#/;
						next if /^$/;
						
						if ($linei =~ /^\[(.*)\]$/) { # get current section
							$current_section = $1; # save current section
						} else {
							if ($linei =~ /^(\d+)\~\~(\d+)$/) {
								die "Error in range: $linei \nArgument 1 shouldn't be bigger than argument 2 \n" if ($1 >= $2);
								#warning "Got range $1 and $2 \n";
								for (my $i = $1; $i <= $2; $i++) {
									#warning "Adding $i \n";
									push (@{$hash_ref->{$current_section}}, $i);
								}
							} else {
								push (@{$hash_ref->{$current_section}}, $linei); # push current line to %hash{section}
							}
						}
					}
					close FILEINCLUDED;
					next;
				}
				
				if ($line =~ /^\[(.*)\]$/) { # get current section
					$current_section = $1; # save current section
				} else {
					if ($line =~ /^(\d+)\~\~(\d+)$/) {
						die "Error in range: $line \nArgument 1 shouldn't be bigger than argument 2 \n" if ($1 >= $2);
						#warning "Got range $1 and $2 \n";
						for (my $i = $1; $i <= $2; $i++) {
							#warning "Adding $i \n";
							push (@{$hash_ref->{$current_section}}, $i);
						}
					} else {
						push (@{$hash_ref->{$current_section}}, $line); # push current line to %hash{section}
					}
				}
				return 0 unless $current_section; # return if our first line isn't a section
		}
	close FILE;
	
	return 1;
}

sub parseConfigArray {
	my ($array_ref) = shift;
	my %return_pairs;
	foreach	(@{$array_ref}) {
		my ($k, $v) = split(/\s+/,$_,2);
		$return_pairs{$k} = $v;
	}
	return %return_pairs;
}
	
	
	
1;