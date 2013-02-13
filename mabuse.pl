#!/usr/bin/perl
# denao - 2002 - davieira@gmail.com
########################################################################################
#   TO DO:
#   * Add a "verbose" option to print the test output on the server as well (when used
#   in daemon mode)
#   * Add an -l(L) option to output to a LOGFILE
########################################################################################
#   Use: perl mabuse.pl [options] <server>
#     Options:
#         -c (to specify a different config file ex.: mabuse.conf)
#         -f (to force exit if found any errors)
#         -d (daemon mode)
#         -h (help screen)
#         <server>  = server name or IP Address
########################################################################################
# NOTES:
# The script expects the DOMAIN set. You can always set it on the Host.
# By default, if there's no server name on the command line, it will assume a self test
# on localhost.
########################################################################################
use Socket;
use Net::hostent;
$version="0.6";
$main::SIG{'INT'} = 'mataSock';
$main::SIG{'PIPE'} = 'RodadeNovo';

print "** Mail Abuse $version - Author: Denis A.V.Jr. <davieira at gmail dot com> ** \n";
parseia_opcoes();
print "** Using config: $configfile.\n";
daemonizeit() if $daemonmode;
testa_host($maquina);

sub logmsg { print "$0 $$: @_ em ", scalar localtime, "\n" }

sub daemonizeit {
  my $paddr;
  my $portabind=shift || 23;
  my $protobind=getprotobyname('tcp');
  socket(S, PF_INET, SOCK_STREAM, $protobind)||die "socket: $!";
  setsockopt(S,SOL_SOCKET, SO_REUSEADDR,pack("l", 1)) || die "setsockopt: $!";
  bind(S, sockaddr_in($portabind, INADDR_ANY)) || die "bind: $!";
  listen(S,SOMAXCONN) || die "listen: $!";
  logmsg "servidor iniciado na porta $portabind";
  for ( ; $paddr=accept(C,S); close C) {
       my($portabind,$iaddr)=sockaddr_in($paddr);
       my $end_mailserver=inet_ntoa($iaddr);
       logmsg "cliente [ $end_mailserver ] usando a porta $portabind";
       select(C);$|=1;select(S);$|=1;select(STDOUT);
       testa_host($end_mailserver);
  }
}

sub testa_host {
   $mailServer=shift;
   if ($mailServer eq "" or $mailServer=~/\-\S/) { $mailServer='localhost'; }
   $proto=getprotobyname("tcp")||6;
   $port=getservbyname("SMTP","tcp")||25;
   $h=gethost($mailServer);
   $serverAddr=inet_ntoa($h->addr);
   $serverName=$h->name;
   $iaddr=inet_aton($mailServer);
   $paddr=sockaddr_in($port,$iaddr);

   socket(SMTP, AF_INET(), SOCK_STREAM(), $proto) or die("Socket: $!");
   connect(SMTP, $paddr) or nao_conectou($serverAddr);
   print C "** Mail Abuse $version - Author: Denis A.V.Jr. <davieira at gmail dot com>\n";
   print C "** This is a script to test your SMTP relay against SPAM\n";
   print C "** This test can take a while\n\n";
   print C "Starting tests, please wait...\n"; sleep(2);
   select(SMTP);$|=1;select(STDOUT);

   recv(SMTP, $banner, 200, 0);
   sendSMTP("HELO cygnus.mail-abuse.org\n");
   $/=":Teste Relay:";
   open (CONF,"$configfile") || die "Could not open config file ($configfile)...\n";
   while (<CONF>) {
     if ($_=~/\S+/) {
         @cmp=split (/\n/,$_);
         for ($i=0;$i<$#cmp;$i++) {
              $cmp[$i]=~s/(?:DE:|PARA:)//;
              $cmp[$i]=~s/\%HOSTNAME\%/$serverName/;
              $cmp[$i]=~s/\%HOSTIP\%/$serverAddr/;
         }
         if ($cmp[0] and $cmp[1] and $cmp[2]) {
             print "\nSPAM test - $cmp[0]\n\n" if !$daemonmode;
             print C "\nSPAM test - $cmp[0]\n\n" if $daemonmode;
             sendSMTP("MAIL From: $cmp[1]\n");
             if ((sendSMTP("RCPT To: $cmp[2]\n")) == 250) {
                 $msgerro="#######<  >< ><> Found a breach! <>< ><  >#######";
                 if ($forcemode==1) {
                     print C "\n$msgerro\n\n" if $daemonmode;
                     die "\n$msgerro\n\n"if !$daemonmode;
                     close(C);
                 } else { $erro = "$msgerro\n\n"; }
             }
             sendSMTP("RSET\n");
         }
     }
   }
   close (CONF);
   close(SMTP);

   print "\n\n### Banner from the tested machine: \n### $banner\n" if !$daemonmode;
   print C "\n\n### Banner from the tested machine: \n### $banner\n" if $daemonmode;
   if ($erro) {
       print "$erro\n" if !$daemonmode;
       print C "$erro\n" if $daemonmode;
   } else {
       print "Server looks protected\n" if !$daemonmode;
       print C "Server looks protected\n" if $daemonmode;
   }
}

sub mataSock {
    close(SMTP);
    close(S) if $daemonmode;
    die("SMTP socket finished (SIGINT)\n");
}

sub RodadeNovo {
    close(SMTP);
    close(S) if $daemonmode;
    daemonizeit();
}
sub sendSMTP {
    my($buffer)=@_;
    print (">>> $buffer") if !$daemonmode;
    print C (">>> $buffer") if $daemonmode;
    send(SMTP,$buffer,0);
    recv(SMTP,$buffer,200,0);
    print ("<<< $buffer") if !$daemonmode;
    print C ("<<< $buffer") if $daemonmode;
    return( (split(/ /,$buffer))[0] );
}

sub parseia_opcoes {
    for ($i=0; $i<=$#ARGV;$i++) {
         if ($ARGV[$i]=~/\-h/) { uso(); }
         if ($ARGV[$i]=~/\-f/) { $forcemode=1; next; }
         if ($ARGV[$i]=~/\-d/) { $daemonmode=1; next; }
         if ($ARGV[$i]=~/\-v/) { $verbosemode=1; next; }
         if ($ARGV[$i]=~/\-c/i) { $configfile=$ARGV[$i+1]; next; }
    }
    if ($ARGV[$#ARGV] !~/\-(h|f|d|c)/i and $ARGV[$#ARGV] ne "") {
        $maquina=$ARGV[$#ARGV];
    } else { $maquina='localhost'; }
    $configfile="mailabuse.conf" if (!$configfile);
}

sub uso {
    print "Use: $0 [options] <SERVER>\n";
    print "Options:\n";
    print "\t-c\t to specify a different config file ex.: mabuse.conf\n";
    print "\t-d\t (daemon mode - Listens on port 23)\n";
    print "\t-f\t (to force exit if found any errors)\n";
    print "\t-h\t (help screen)\n\n";
    exit(0);
}

sub nao_conectou {
   $ipdum=shift;
   if ($daemonmode) {
       print C "** Could not open a connection on your server ($ipdum:25) : $!\n";
       print C "** Aborting ** \n"; close C;
   }
}
