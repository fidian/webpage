Webpage Grabber
===============

This is an email to web gateway service.  It uses fetchmail to receive emails, procmail to match emails against rules, then either links or wget to retrieve files.


Setup
-----

1. Ensure you have wget, zip, mime-construct, fetchmail, procmail and a working SMTP server (I am using msmtp).
2. Install LWP, LWP::Protocol::https and HTML::TokeParser via CPAN so Perl can run `url.pl`.  On Ubuntu you need libnet-ssleay-perl and libcrypt-ssleay-perl for Net:SSLeay to work.
3. Test `url.pl` and ensure it works.  You may need to update `Text::Wrap`.

        echo -n "" | ./url.pl -t https://www.yahoo.com

4. Copy `fetchmailrc-template` to `fetchmail.
5. Change permissions on `fetchmail`: `chmod 0600 fetchmail`
6. Run `touch fetchmail.log` to create the log file.
7. Install a MTA.  I'm using msmtp because I don't want to run my own server.  ([more info](https://wiki.archlinux.org/index.php/Msmtp))
8. Test by running `fetchmail -f ~/webpage/fetchmail`
9. Once that works, set up a cron job to run fetchmail.

        @reboot fetchmail -f webpage/fetchmailrc > /dev/null 2>&1
