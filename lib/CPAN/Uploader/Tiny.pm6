use v6;
unit class CPAN::Uploader::Tiny:ver<0.0.1>;

use CPAN::Uploader::Tiny::MultiPart;
use HTTP::Tinyish;

has $.url = %*ENV<CPAN_UPLOADER_UPLOAD_URI> || 'https://pause.perl.org/pause/authenquery';
has $.user;
has $.password;

method new($user, $password) {
    self.bless(:$user, :$password);
}

method new-from-config($file) {
    my %config = self!read-config($file);
    self.new(%config<user>, %config<password>);
}

method !read-config($file) {
    die "missing $file" unless $file.IO.e;
    if try $file.IO.slurp(:!bin) {
        self!read-plain-config(:$file);
    } else {
        self!read-encrypted-config(:$file);
    }
}

method !read-plain-config(:$file, :@line) {
    @line ||= $file.IO.lines;
    my %config = gather for @line -> $line {
        if $line ~~ /^ $<key>=(\S+) \s+ $<value>=(\S.*)/ {
            take $<key>.Str => $<value>.Str;
        }
    };
    %config<user> or die "missing user in $file";
    %config<password> or die "missing password in $file";
    %config;
}

method !read-encrypted-config(:$file) {
    my $proc = run "gpg", "-qd", "--no-tty", $file, :out, :err;
    if $proc.exitcode != 0 {
        my $err = $proc.err.slurp;
        my $exitcode = $proc.exitcode;
        die $err ?? $err !! "gpg failed, exitcode = $exitcode";
    }
    my @line = $proc.out.lines;
    self!read-plain-config(:$file, :@line);
}

method upload($tarball, :$subdirectory, :$async) {
    my $url = $!url.subst('//', "//{$.user}:{$.password}@");

    my $multi = CPAN::Uploader::Tiny::MultiPart.new;
    $multi.add-content('HIDDENNAME', $!user);
    $multi.add-content('CAN_MULTIPART', "1");
    $multi.add-content('pause99_add_uri_uri', '');
    $multi.add-content('SUBMIT_pause99_add_uri_httpupload', ' Upload this file from my disk ');
    $multi.add-file('pause99_add_uri_httpupload',
        filename => $tarball.IO.basename,
        content => $tarball.IO.slurp(:bin),
        content-type => 'application/gzip',
    );
    my ($boundary, $content) = $multi.finalize;

    my %option =
        headers => {
            content-type => "multipart/form-data; boundary=$boundary",
        },
        content => $content,
    ;
    my &cb = sub (%res) {
        return True if %res<success>;
        die "%res<status> %res<reason>, $!url";
    };

    if $async {
        return HTTP::Tinyish.new(:async).post($url, |%option).then: -> $p { &cb($p.result) };
    } else {
        return &cb( HTTP::Tinyish.new.post($url, |%option) );
    }
}

=begin pod

=head1 NAME

CPAN::Uploader::Tiny - Upload tarballs to CPAN

=head1 SYNOPSIS

  use CPAN::Uploader::Tiny;

  my $uploader = CPAN::Uploader::Tiny.new-from-config("%*ENV<HOME>/.pause");
  $uploader.upload("Your-Perl6-Module-0.0.1.tar.gz");

=head1 DESCRIPTION

CPAN::Uploader::Tiny uploads tarballs to CPAN.

=head1 SEE ALSo

L<https://github.com/rjbs/CPAN-Uploader>

L<https://github.com/Leont/cpan-upload-tiny>

=head1 AUTHOR

Shoichi Kaji <skaji@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright 2017 Shoichi Kaji

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
