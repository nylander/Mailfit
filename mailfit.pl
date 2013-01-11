#!/usr/bin/perl
 
# NAME:    mailfit.pl
# BY:      Johan Nylander
# WHAT:    Runs modeltest/mrmodeltest2 on file and
#          optionally e-mails the results to user.
# WARNING: Experimental version. No extensive error checking!
#          E-mailing might not work on all systems!
# INFO:    Type "perldoc mailfit.pl" or "mailfit.pl -man"
#          for more information


use warnings;
use strict;
use Getopt::Long;
use Pod::Usage;


### Globals
my $SCRIPTNAME       = 'mailfit.pl';
my $CHANGES          = '06/23/2006 03:10:09';
my $VERSION          = '0.2 experimental';
my $OUTFILEEXTENSION = '.mfit.out'; 
my $LOGFILEEXTENTION = '.mfit.log'; 
my $PAUPCOMMANDFILE  = 'mfit_paup_commads';
my $TMPSENDFILE      = 'mfit_tmp_sendfile';

my $user             = '';   # UNIX username
my $emailAddress     = '';   # Defaults to unixuser@domain
my $sendMail         = 'NO'; # Don't send email as default
my $useModeltest     = 'NO'; # Use MrModeltest2 as default
my $paup             = '';   # paup binary
my $mrmodeltest2     = '';   # MrModeltest2 binary
my $modeltest        = '';   # Modeltest binary
my $mutt             = '';   # mutt binary
my $mail             = '';   # mail binary
my $inFile           = '';  
my $outFile          = '';  
my $logFile          = '';  
my $modeltestOption  = '';
my $emailOption      = '';
my $sendtoOption     = '';


### Handle arguments
if (@ARGV < 1 or @ARGV > 5) {
    print "\n Try '$SCRIPTNAME --help' for more info\n\n";
}
else {

    GetOptions( 'help'         => sub { pod2usage(1); },
                'version'      => sub { print "\n  $SCRIPTNAME version $VERSION\n  Last changes $CHANGES\n"; exit(0) },
                'man'          => sub { pod2usage(-exitstatus => 0, -verbose => 2); },
                'modeltest'    => \$modeltestOption,
                'email'        => \$emailOption,
                'sendto=s'     => \$sendtoOption
              );

    if (@ARGV ) {
        $inFile = shift @ARGV;
        die "\a\n Couldn't find infile: $!" unless (-s $inFile);
    }
    else {
        print "\n Couldn't find an infile.\n\n Try '$SCRIPTNAME --help' for more information.\n\n";
        exit(0);
    }    
    
    $outFile = "$inFile" . "$OUTFILEEXTENSION";
    $logFile = "$inFile" . "$LOGFILEEXTENTION";


    ### Print some info
    open (PRINTONTWO, "| tee $logFile") or die "\a\nCouldn't open logfile for writing: $!\n";
    print PRINTONTWO "\n Starting $SCRIPTNAME\n\n";
    print PRINTONTWO " Infile  is: $inFile\n";
    print PRINTONTWO " Outfile is: $outFile\n";
    print PRINTONTWO " Logfile is: $logFile\n";


    ### MrModeltest2 or Modeltest
    if ($modeltestOption) {
        $useModeltest = 'YES';
        print PRINTONTWO " Will use Modeltest.\n";
    }
    else {
        print PRINTONTWO " Will use MrModeltest2.\n";
    }


    ### Send e-mail or not
    if ($sendtoOption) {
        $sendMail = 'YES';
        CheckMailApps(); # Check if mutt or mail can be found
        $emailAddress = $sendtoOption;
    }
    elsif ($emailOption) {
        $sendMail = 'YES';
        CheckMailApps();
        chomp($user = `whoami`);
        $emailAddress = $user;
    }
    
    if ($sendMail eq 'NO') {
        print PRINTONTWO " Will not send you the result via e-mail.\n";
    }
    elsif ($sendMail eq 'YES') {
        print PRINTONTWO " Will try to send results to: $emailAddress\n";
    }


    ### Check if modeltest/mrmodeltest2 and paup can be found
    CheckApps();


    ### Build a command file for PAUP
    BuildPaup();


    ### Run PAUP
    print PRINTONTWO " Starting PAUP in background. Will tell when finished...\n";
    system "$paup -n $PAUPCOMMANDFILE > /dev/null";
    print PRINTONTWO " PAUP is finished.\n";


    ### Run MrModeltest or Modeltest
    if ($useModeltest eq 'YES') {
        # Run Modeltest
        print PRINTONTWO " Running Modeltest.\n";
        system "$modeltest < model.scores > $outFile";
        die "\n Modeltest failure ($!) -- Saving $PAUPCOMMANDFILE, modelfit.log, and model.scores files\n"
            unless (-s "$outFile");
        print PRINTONTWO " Modeltest is finished.\n\n";
        unlink ("$PAUPCOMMANDFILE", "model.scores", "modelfit.log"); # Remove files without warning!
    }
    else {
        # Run MrModeltest2
        print PRINTONTWO " Running MrModeltest2.\n";
        system "$mrmodeltest2 < mrmodel.scores > $outFile";
        die "\n MrModeltest2 failure ($!) -- Saving $PAUPCOMMANDFILE, mrmodelfit.log, and mrmodel.scores files\n"
            unless (-s "$outFile");
        print PRINTONTWO " MrModeltest2 is finished.\n\n";
        unlink ("$PAUPCOMMANDFILE", "mrmodel.scores", "mrmodelfit.log"); # Remove files without warning!
    }
    print PRINTONTWO "----------------------------------------\n";


    ### Find and print the selected models
    open (MFITOUT, '<', $outFile) or die "\a\nCan't open out file: $!\n\n";
    while (<MFITOUT>) {
    	print PRINTONTWO if /selected:/;
    }
    close (MFITOUT) or warn "\nCouldn't close out file: $!\n";
    print PRINTONTWO "----------------------------------------\n\n";
    print PRINTONTWO " First model above selected using LRT,\n";
    print PRINTONTWO " second model above selected using (approx.) AIC.\n";
    print PRINTONTWO " Details can be found in file \"$outFile.\"\n";
    print PRINTONTWO " This output can also be found in file \"$logFile.\"\n\n";


    ### Mail the result to user
    if ($sendMail eq 'NO') {
        print PRINTONTWO "\n Done. \n";
        exit(0);
    }
    elsif ($mutt ne '') {
        system "mutt $emailAddress -s \"$inFile is ready\" -a $outFile < $logFile";
        print PRINTONTWO " Mutt send the results to $emailAddress\n";
    }
    elsif ($mail ne '') {
        system "cat $logFile $outFile > $TMPSENDFILE";
        system "mail $emailAddress -s \"$inFile is ready\" < $TMPSENDFILE";
        unlink "$TMPSENDFILE";
        print PRINTONTWO " Mail send the results to $emailAddress\n";
    }


    ### Done
    print PRINTONTWO "\n Done. \n";
    close(PRINTONTWO) or warn "\nCouldn't close log file: $!\n";
    
    exit(0);
}



#===  FUNCTION  ================================================================
#         NAME:  CheckApps()
#  DESCRIPTION:  Check if Modeltest/MrModeltest2 and PAUP is in the PATH
#   PARAMETERS:  none 
#      RETURNS:  sets globals $paup, $modeltest, $mrmodeltest2
#===============================================================================
sub CheckApps {

    # Check if paup can be found
    $paup = '';
    FIND_PAUP:
    foreach (split(/:/,$ENV{PATH})) {
        if (-x "$_/paup") {
            $paup = "$_/paup";
            last FIND_PAUP;
        }
    }

    if ($paup eq '') {
        die qq(\a\nCouldn\'t find executable "paup" (check your path).\n\n);
    }

    if ($useModeltest eq 'YES') {
        # Check if modeltest can be found
        $modeltest = '';
        FIND_MODELTEST:
        foreach (split(/:/,$ENV{PATH})) {
            if (-x "$_/modeltest") {
                $modeltest = "$_/modeltest";
                last FIND_MODELTEST;
            }
        }

        if ($modeltest eq '') {
            die qq(\a\nCouldn\'t find executable "modeltest" (check your path).\n\n);
        }
    }
    else {
       # Check if mrmodeltest2 can be found
        $mrmodeltest2 = '';
        FIND_MRMODELTEST2:
        foreach (split(/:/,$ENV{PATH})) {
            if (-x "$_/mrmodeltest2") {
                $mrmodeltest2 = "$_/mrmodeltest2";
                last FIND_MRMODELTEST2;
            }
        }

        if ($mrmodeltest2 eq '') {
            die qq(\a\nCouldn\'t find executable "mrmodeltest2" (check your path).\n\n);
        }
    }
}


#===  FUNCTION  ================================================================
#         NAME:  CheckMailApps()
#  DESCRIPTION:  Checks if mut or mail can be found.
#                If neither are found, sets global $sendmail = 'NO'
#   PARAMETERS:  None
#      RETURNS:  Sets globals $mutt, $mail, $sendmail
#===============================================================================
sub CheckMailApps {

    # Find mutt
    $mutt = '';
    FIND_MUTT:
    foreach (split(/:/,$ENV{PATH})) {
        if (-x "$_/mutt") {
            $mutt = "$_/mutt";
            last FIND_MUTT;
        }
    }

    # If no mutt - look for mail
    if ($mutt eq '') {
        $mail = '';
        FIND_MAIL:
        foreach (split(/:/,$ENV{PATH})) {
            if (-x "$_/mail") {
                $mail = "$_/mail";
                last FIND_MAIL;
            }
        }

        # If no mail - don't send
        if ($mail eq '') {
            print PRINTONTWO qq(\a\n Warning: Couldn\'t find executables "mutt" or "mail".\n\n);
            $sendMail = 'NO';
        }
    }
}


#===  FUNCTION  ================================================================
#         NAME:  BuildPaup()
#  DESCRIPTION:  Creates a command file for paup
#   PARAMETERS:  None
#      RETURNS:  
#===============================================================================
sub BuildPaup {

    open (COMMANDS, '>', $PAUPCOMMANDFILE) or die "\a\nCan't open paup command file: $!\n\n";

    print COMMANDS "\nBEGIN PAUP;\nset warnreset=no notifybeep=no autoclose=yes;\nEND;\n";

    open (DATACONTENT, '<', $inFile) or die "\a\nCan't open in file: $!\n\n";

    while (<DATACONTENT>) {
        print COMMANDS;
    }

    close (DATACONTENT) or warn "\nCouldn't close datacontent file: $!\n";
    
    PrintModelBlock();

    print COMMANDS "\nquit warntsave=no;";

    close (COMMANDS) or warn "\nCouldn't close paup command file: $!\n";
}


#===  FUNCTION  ================================================================
#         NAME:  PrintModelBlock()
#  DESCRIPTION:  Appends the MrModelblock/modelblockPAUPb10 to
#                the paup command file
#   PARAMETERS:  None
#      RETURNS:  None
#===============================================================================
sub PrintModelBlock {

    my $scoreFile = '';
    my $mlogFile = '';

    if ($useModeltest eq 'YES') {
        $scoreFile = 'model.scores';
        $mlogFile = 'modelfit.log';
    }
    else {
        $scoreFile = 'mrmodel.scores';
        $mlogFile = 'mrmodelfit.log';
    }
    
    print COMMANDS qq (
    Begin Paup;
    	Log file=$mlogFile replace;
    	DSet distance=JC objective=ME base=equal rates=equal pinv=0 subst=all negbrlen=setzero;
    	NJ showtree=no breakties=random;
    	Default lscores longfmt=yes;
    	Set criterion=like;
    	lscores 1/ nst=1 base=equal rates=equal pinv=0 scorefile=$scoreFile replace;
    	lscores 1/ nst=1 base=equal rates=equal pinv=est scorefile=$scoreFile append;
    	lscores 1/ nst=1 base=equal rates=gamma shape=est pinv=0 scorefile=$scoreFile append;
    	lscores 1/ nst=1 base=equal rates=gamma shape=est pinv=est scorefile=$scoreFile append;
    	lscores 1/ nst=1 base=est rates=equal pinv=0 scorefile=$scoreFile append;
    	lscores 1/ nst=1 base=est rates=equal pinv=est scorefile=$scoreFile append;
    	lscores 1/ nst=1 base=est rates=gamma shape=est pinv=0 scorefile=$scoreFile append;
    	lscores 1/ nst=1 base=est rates=gamma shape=est pinv=est scorefile=$scoreFile append;
    	lscores 1/ nst=2 base=equal tratio=est rates=equal pinv=0 scorefile=$scoreFile append;
    	lscores 1/ nst=2 base=equal tratio=est rates=equal pin=est scorefile=$scoreFile append; 
    	lscores 1/ nst=2 base=equal tratio=est rates=gamma shape=est pinv=0 scorefile=$scoreFile append;
    	lscores 1/ nst=2 base=equal tratio=est rates=gamma shape=est pinv=est scorefile=$scoreFile append;
    	lscores 1/ nst=2 base=est tratio=est rates=equal pinv=0 scorefile=$scoreFile append;
    	lscores 1/ nst=2 base=est tratio=est rates=equal pinv=est scorefile=$scoreFile append; 
     	lscores 1/ nst=2 base=est tratio=est rates=gamma shape=est pinv=0 scorefile=$scoreFile append; 
    	lscores 1/ nst=2 base=est tratio=est rates=gamma shape=est pinv=est scorefile=$scoreFile append;
);
    if ($useModeltest eq 'YES') {
        print COMMANDS qq (
            lscores 1/ nst=6 base=equal rmat=est rclass=(a b a a e a) rates=equal pinv=0 scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=equal rmat=est rates=equal pinv=est scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=equal rmat=est rates=gamma shape=est pinv=0 scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=equal rmat=est rates=gamma shape=est pinv=est scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=est rmat=est rates=equal pinv=0 scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=est rmat=est rates=equal pinv=est scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=est rmat=est rates=gamma shape=est pinv=0 scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=est rmat=est rates=gamma shape=est pinv=est scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=equal rmat=est rclass=(a b c c b a) rates=equal pinv=0 scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=equal rmat=est rates=equal pinv=est scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=equal rmat=est rates=gamma shape=est pinv=0 scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=equal rmat=est rates=gamma shape=est pinv=est scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=est rmat=est rates=equal pinv=0 scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=est rmat=est rates=equal pinv=est scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=est rmat=est rates=gamma shape=est pinv=0 scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=est rmat=est rates=gamma shape=est pinv=est scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=equal rmat=est rclass=(a b c c e a) rates=equal pinv=0 scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=equal rmat=est rates=equal pinv=est scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=equal rmat=est rates=gamma shape=est pinv=0 scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=equal rmat=est rates=gamma shape=est pinv=est scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=est rmat=est rates=equal pinv=0 scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=est rmat=est rates=equal pinv=est scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=est rmat=est rates=gamma shape=est pinv=0 scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=est rmat=est rates=gamma shape=est pinv=est scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=equal rmat=est rclass=(a b c d b e) rates=equal pinv=0 scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=equal rmat=est rates=equal pinv=est scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=equal rmat=est rates=gamma shape=est pinv=0 scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=equal rmat=est rates=gamma shape=est pinv=est scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=est rmat=est rates=equal pinv=0 scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=est rmat=est rates=equal pinv=est scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=est rmat=est rates=gamma shape=est pinv=0 scorefile=$scoreFile append; 
            lscores 1/ nst=6 base=est rmat=est rates=gamma shape=est pinv=est scorefile=$scoreFile append; 
);
    }
    print COMMANDS qq (	
         	lscores 1/ nst=6 base=equal rmat=est rclass= (a b c d e f) rates=equal pinv=0 scorefile=$scoreFile append; 
         	lscores 1/ nst=6 base=equal rmat=est rates=equal pinv=est scorefile=$scoreFile append; 
         	lscores 1/ nst=6 base=equal rmat=est rates=gamma shape=est pinv=0 scorefile=$scoreFile append; 
        	lscores 1/ nst=6 base=equal rmat=est rates=gamma shape=est pinv=est scorefile=$scoreFile append;
        	lscores 1/ nst=6 base=est rmat=est rates=equal pinv=0 scorefile=$scoreFile append; 
        	lscores 1/ nst=6 base=est rmat=est rates=equal pinv=est scorefile=$scoreFile append; 
        	lscores 1/ nst=6 base=est rmat=est rates=gamma shape=est pinv=0 scorefile=$scoreFile append; 
        	lscores 1/ nst=6 base=est rmat=est rates=gamma shape=est pinv=est scorefile=$scoreFile append;
        	Log stop=yes;
        End;
);
}


__END__


### POD documentation

=pod


=head1 NAME

mailfit.pl


=head1 VERSION

Documentation for mailfit.pl version 0.1 experimental


=head1 SYNOPSIS

B<mailfit.pl> [B<--modeltest>][B<--email>][B<--sendto=>I<user@domain>][B<--help>][B<--version>][B<--man>] F<FILE>


=head1 DESCRIPTION

Runs PAUP* and MrModeltest2 (or Modeltest) on F<FILE>,
and then (optionally) sends the result via e-mail.

F<FILE> should be DNA sequences in Nexus format.

The results from MrModeltest2 or Modeltest are written
to a file named F<FILE.mfit.out>, and a log file
is written to F<FILE.mfit.log>.


=head1 OPTIONS

Mandatory arguments to long options are mandatory for short options too


=over 8

=item B<-mo, --modeltest>

Use Modeltest and not MrModeltest2 (MrModeltest2 is the default).
Basically tests 56 models instead of 24.


=item B<-e, --email>

Send the result via e-mail to the users standard UNIX account.


=item B<-s, --sendto=>I<name@domain>

Send the result via e-mail to I<name@domain>.


=item B<-h, --help>

Prints help message and exits.


=item B<-v, --version>

Prints version message and exits.


=item B<-ma, --man>

Displays the manual page.


=back

=head1 USAGE

Run Modeltest (and not MrModeltest2) and
send the results to my UNIX e-mail account:

=over 12

=item B<mailfit.pl --modeltest --email> F<FILE>

=item B<mailfit.pl -mo -e> F<FILE>

=back

Run MrModeltest2 (and not Modeltest)
and send the result to I<bob@home>:


=over 12

=item B<mailfit.pl --sendto=>I<bob@home> F<FILE>

=item B<mailfit.pl -s=>I<bob@home> F<FILE>

=back


To run MrModeltest2 on F<FILE> locally,
without sending any e-mails:


=over 12

=item B<mailfit.pl> F<FILE>

=back

=head1 AUTHOR

Written by Johan A. A. Nylander


=head1 REPORTING BUGS

Please report any bugs to I<nylander @ scs.fsu.edu>.


=head1 DEPENDENCIES

=over 12

=item B<PAUP*>

=item B<MrModeltest2> or B<Modeltest>

=item B<mutt> or B<mail>

=back


Minimally, B<PAUP*> and B<MrModeltest2> and/or 
B<Modeltest> needs to be installed (I<and named>
B<paup>, B<mrmodeltest2>, B<modeltest>).
In order for results to be send via e-mail,
the user must have a e-mail account on the
server where the job is launched.
Mailfit.pl tries to use B<mutt>, then B<mail> as
mail clients. No e-mails are send if none
of these programs are found on the server.

Note that the success of the e-mail functionality
is heavily dependent on how the system is configured,
and mailfit.pl does not do extensive error checking!


=head1 LICENSE AND COPYRIGHT

Copyright (c) 2005, 2006 Johan Nylander. All rights reserved.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details. 
http://www.gnu.org/copyleft/gpl.html 


=cut

