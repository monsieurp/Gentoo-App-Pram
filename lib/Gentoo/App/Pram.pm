#!/usr/bin/env perl
package Gentoo::App::Pram;

use warnings;
use strict;

use feature 'say';

use Term::ANSIColor qw/:constants colored/;
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

my $vars;

sub run {
    my ($self, $argv) = @_;

    my $pr_number = shift @{$argv};

    $opts{help} and pod2usage(-verbose => 1);
    $opts{man} and pod2usage(-verbose => 2);

    $pr_number || pod2usage(
        -message => "$error! You must specify a PR number!\n",
        -verbose => 1
    );
    
    $pr_number =~ /^\d+$/ || pod2usage(
        -message => "$error! \"$pr_number\" is NOT a number!\n",
        -verbose => 1
    );


    # Variables used throughout the script.
    $vars = {
        # Defaults to 'gentoo/gentoo' because we're worth it.
        repo_name   => $opts{repository} || 'gentoo/gentoo',
        git_command => which('git') . ' am -s -S',
        pr_number   => $pr_number,
        editor      => $opts{editor} || $ENV{EDITOR} || 'less'
    };

    $vars->{git_url} =
        "https://patch-diff.githubusercontent.com/raw/$vars->{repo_name}/pull";
    
    # Go!
    $self->apply_patch($self->format_patch($self->fetch_patch()));
}

sub fetch_patch {
    my $self = shift;

    my ($pr_number, $git_url) = ($vars->{pr_number}, $vars->{git_url});

    say "$ok! Getting PR $pr_number...";

    my $patch_name = "$pr_number.patch";
    my $patch_url = "$git_url/$patch_name";

    my $response = HTTP::Tiny->new->get($patch_url);
    my $status = $response->{status};
    
    $status != 200 and die "$error! Got HTTP status $status when querying URL '$patch_url'!";
    
    my $patch = $response->{content};
    chomp $patch;
    
    return decode('UTF-8', $patch);
}

sub format_patch {
    my ($self, $patch) = @_;

    my ($pr_number, $repo_name) = ($vars->{pr_number}, $vars->{repo_name});

    my $close_url = "https://github.com/$repo_name/pull/$pr_number";
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
    
    return join '', @patch;
}

sub apply_patch {
    my ($self, $patch) = @_;

    my $patch_location = File::Temp->new() . '.patch';
    
    open my $fh, '>:encoding(UTF-8)', $patch_location || die "$error! Can't write to $patch_location: $!!";
    print $fh $patch;
    close $fh;

    my ($pr_number, $editor, $git_command) = 
        ($vars->{pr_number}, $vars->{editor}, $vars->{git_command});
    
    system $editor => $patch_location;
    
    print "$merge? Do you want to apply this patch and merge PR $pr_number? [y/n] ";
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
    
    unlink $patch_location || die "$error! Couldn't remove '$patch_location'!";
    say "$ok! Removed '$patch_location'!";
}

1;

__END__

=head1 NAME

Gentoo::App::Pram - Backend module for the pram script.

=head1 AUTHOR

Patrice Clement <monsieurp@gentoo.org>

=cut
