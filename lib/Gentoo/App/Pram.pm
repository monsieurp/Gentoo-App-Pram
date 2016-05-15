#!/usr/bin/env perl
package Gentoo::App::Pram;

use warnings;
use strict;

use feature 'say';

use Term::ANSIColor qw/:constants colored/;
use File::Basename qw/basename/;
use File::Which qw/which/;
use Encode qw/decode/;
use File::Temp;
use HTTP::Tiny;

use Getopt::Long;
use Pod::Usage;

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

my $error = colored('ERROR', 'red');
my $no    = colored('NO', 'red');

my $yes   = colored('YES', 'green');
my $ok    = colored('OK', 'green');

my $merge = colored('MERGE', 'blue');

$| = 1;

sub run {
    my ($self, $argv) = @_;

    my $pr_number = shift @{$argv};

    $opts{help} and pod2usage(-verbose => 1);
    $opts{man} and pod2usage(-verbose => 2);

    $pr_number || pod2usage(
        -message => "$error! You must specify a Pull Request number!\n",
        -verbose => 1
    );
    
    $pr_number =~ /^\d+$/ || pod2usage(
        -message => "$error! \"$pr_number\" is NOT a number!\n",
        -verbose => 1
    );

    # Defaults to 'gentoo/gentoo' because we're worth it.
    my $repo_name   = $opts{repository} || 'gentoo/gentoo';
    my $editor      = $opts{editor} || $ENV{EDITOR} || 'less';

    my $git_command = which('git') . ' am -s -S';
    my $patch_url   = "https://patch-diff.githubusercontent.com/raw/$repo_name/pull/$pr_number.patch";
    my $close_url   = "https://github.com/$repo_name/pull/$pr_number";
    
    # Go!
    $self->apply_patch(
        $editor,
        $git_command,
        $self->add_close_header(
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

sub add_close_header {
    @_ == 3 || die qq#Usage: add_close_header(close_url, patch)\n#;
    my ($self, $close_url, $patch) = @_;

    print "$ok: Adding \"Closes:\" header... ";
    
    my $header = "Closes: $close_url\n---";
    my @patch = ();
    
    if ($patch =~ /Closes:/) {
        for (split /\n/, $patch) {
            chomp;
            push @patch, "$_\n";
        }
    } else {
        for (split /\n/, $patch) {
            chomp;
            if (/(^---$)/) { s/$1/$header/g; }
            push @patch, "$_\n";
        }
    }

    print "OK!\n";

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

Gentoo::App::Pram - Backend module for the pram script.

=head1 AUTHOR

Patrice Clement <monsieurp@gentoo.org>

=cut
