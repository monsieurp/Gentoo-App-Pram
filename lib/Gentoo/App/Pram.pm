#!/usr/bin/env perl
package Gentoo::App::Pram;

use warnings;
use strict;

our $VERSION = '0.001000';

use feature 'say';

use Term::ANSIColor qw/colored/;
use File::Basename qw/basename/;
use File::Which qw/which/;
use Encode qw/decode/;
use File::Temp;
use HTTP::Tiny;

use Getopt::Long;
use Pod::Usage;

sub new {
    my ( $class, @args ) = @_;
    return bless { ref $args[0] ? %{ $args[0] } : @args }, $class;
}

sub new_with_opts {
    my ( $class ) =  @_;
    my @opts = (
        'repository|r=s',
        'editor|e=s',
        'help|h',
        'man|m'
    );
    my %opts;
    GetOptions(
        \%opts,
        @opts
    );
    $opts{pr_number} = shift @ARGV;
    return $class->new(\%opts);
}

my $error = colored('ERROR', 'red');
my $no    = colored('NO', 'red');

my $yes   = colored('YES', 'green');
my $ok    = colored('OK', 'green');

my $merge = colored('MERGE', 'blue');

sub run {
    my ($self) = @_;

    my $pr_number = $self->{pr_number};

    $| = 1;

    $self->{help} and pod2usage(-verbose => 1);
    $self->{man} and pod2usage(-verbose => 2);

    $pr_number || pod2usage(
        -message => "$error! You must specify a Pull Request number!\n",
        -verbose => 1
    );
    
    $pr_number =~ /^\d+$/ || pod2usage(
        -message => "$error! \"$pr_number\" is NOT a number!\n",
        -verbose => 1
    );

    # Defaults to 'gentoo/gentoo' because we're worth it.
    my $repo_name   = $self->{repository} || 'gentoo/gentoo';
    my $editor      = $self->{editor} || $ENV{EDITOR} || 'less';

    my $git_command = which('git') . ' am -s -S';
    my $patch_url   = "https://patch-diff.githubusercontent.com/raw/$repo_name/pull/$pr_number.patch";
    my $close_url   = "https://github.com/$repo_name/pull/$pr_number";
    
    # Go!
    $self->apply_patch(
        $editor,
        $git_command,
        $self->add_closes_header(
            $close_url,
            $self->fetch_patch(
                $patch_url
            )
        )
    );
}

sub fetch_patch {
    @_ == 2 || die qq#Usage: fetch_patch(patch_url)\n#;
    my ($self, $patch_url) = @_;

    print "$ok! Fetching $patch_url... ";

    my $response = HTTP::Tiny->new->get($patch_url);
    my $status = $response->{status};
    
    $status != 200 and die qq#\n$error! Unreachable URL! Got HTTP status $status!\n#;
    
    my $patch = $response->{content};
    chomp $patch;

    print "OK!\n";
    
    return decode('UTF-8', $patch);
}

sub add_closes_header {
    @_ == 3 || die qq#Usage: add_closes_header(close_url, patch)\n#;
    my ($self, $close_url, $patch) = @_;

    print "$ok: Adding \"Closes:\" header... ";
    my $confirm = $no;
    
    my $header = "Closes: $close_url\n---";
    my @patch = ();
    
    for (split /\n/, $patch) {
        chomp;
        # Some folks might add this header already to their PR
        # so don't add it twice.
        if ($patch !~ /Closes:/) {
            if (/(\A---\Z)/) { 
                s/$1/$header/g; 
                $confirm = $yes;
            }
        }
        push @patch, "$_\n";
    }

    print "$confirm!\n";

    return join '', @patch;
}

sub apply_patch {
    @_ == 4 || die qq#Usage: apply_patch(editor, git_command, patch)\n#;
    my ($self, $editor, $git_command, $patch) = @_;

    my $patch_location = File::Temp->new() . '.patch';
    open my $fh, '>:encoding(UTF-8)', $patch_location || die qq#$error! Can't write to $patch_location: $!!\n#;
    print $fh $patch;
    close $fh;

    say "$ok! Opening $patch_location with $editor ...";
    system $editor => $patch_location;
    
    print "$merge? Do you want to apply this patch and merge this PR? [y/n] ";

    chomp(my $answer = <STDIN>);
    if ($answer =~ /^[Yy]$/) {
        $git_command = "$git_command $patch_location";
        say "$yes! Launching '$git_command' ...";
    
        my $exit = system join ' ', $git_command;
        if ($exit eq 0) {
            say "$ok! git am exited gracefully!";
        } else {
            say "$error! git am failed!";
            exit $exit;
        }
    } else {
        say "$no! Bailing out.";
    }
    
    unlink $patch_location || die qq#$error! Couldn't remove '$patch_location'!\n#;
    say "$ok! Removed $patch_location.";
}

1;

__END__

=head1 NAME

Gentoo::App::Pram - Library to fetch a GitHub Pull Request as an am-like patch.

=head1 DESCRIPTION

The purpose of this module is to fetch Pull Requests from GitHub's CDN as
am-like patches in order to facilitate the merging and closing of Pull
Requests.

=head1 FUNCTIONS

=over 4

=item * fetch_patch($patch_url)

Fetch patch from $patch_url. Return patch as a string.

=item * add_closes_header($close_url, $patch)

Add a "Closes:" header to each commit in $patch using $close_url. If the patch already
contains such headers, skip this step.

=item * apply_patch($editor, $git_command, $patch)

Apply $patch onto HEAD of the current git repository using $git_command. This
functions also shows $patch in $editor for a final review.

=back

=head1 VERSION

version 0.001

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2016 by Patrice Clement.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 AUTHOR

Patrice Clement <monsieurp@gentoo.org>

=cut
