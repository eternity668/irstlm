#! /usr/bin/perl

#*****************************************************************************
# IrstLM: IRST Language Model Toolkit
# Copyright (C) 2007 Marcello Federico, ITC-irst Trento, Italy

# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.

# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.

# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301 USA

#******************************************************************************



#first pass: read dictionary and generate 1-grams
#second pass: 
#for n=2 to N
#  foreach n-1-grams
#      foreach  n-grams with history n-1
#          compute smoothing statistics
#          store successors
#      compute back-off probability
#      compute smoothing probability
#      write n-1 gram with back-off prob 
#      write all n-grams with smoothed probability

use strict;
use Getopt::Long "GetOptions";

my $gzip="/usr/bin/gzip";
my $gunzip="/usr/bin/gunzip";


my $ngram;
my($help,$verbose,$size,$freqshift,$ngrams,$sublm,$witten_bell,$kneser_ney,$prune_singletons,$cross_sentence)=();

$help=1 unless
&GetOptions('size=i' => \$size,
            'freq-shift=i' => \$freqshift, 
             'ngrams=s' => \$ngrams,
             'sublm=s' => \$sublm,
             'witten-bell' => \$witten_bell,
             'kneser-ney' => \$kneser_ney,
             'prune-singletons' => \$prune_singletons,
	           'cross-sentence' => \$cross_sentence,
             'help' => \$help,
             'verbose' => \$verbose);


if ($help || !$size || !$ngrams || !$sublm){
  print "build-sublm.pl <options>\n",
        "--size <int>        maximum n-gram size for the language model\n",
        "--ngrams <string>   input file or command to read the ngram table\n",
        "--sublm <string>    output file prefix to write the sublm statistics \n",
        "--freq-shift <int>  (optional) value to be subtracted from all frequencies\n",
        "--kneser-ney         use approximate kneser-ney smoothing\n",
        "--witten-bell        (default) use witten bell smoothin\n",
        "--prune-singletons   remove n-grams occurring once, for n=3,4,5,... \n",
        "--cross-sentence     (optional) include cross-sentence bounds\n",
        "--help              (optional) print these instructions\n";    

  exit(1);
}

$witten_bell++ if !$witten_bell && !$kneser_ney;

warn "build-sublm: size $size ngrams $ngrams sublm $sublm witten-bell $witten_bell kneser-ney $kneser_ney cross-sentence $cross_sentence\n"
if $verbose;


die "build-sublm: value of --size must be larger than 0\n" if $size<1;
die "build-sublm: choose one smoothing method\n" if $witten_bell && $kneser_ney;

my $log10=log(10.0);  #service variable to convert log into log10

my $oldwrd="";      #variable to check if 1-gram changed 

my @cnt=();         #counter of n-grams
my $totcnt=0;       #total counter of n-grams
my ($ng,@ng);      #read ngrams
my $ngcnt=0;        #store ngram frequency
my $n;

warn "Collecting 1-gram counts\n";

open(INP,"$ngrams") || open(INP,"$ngrams|")  || die "cannot open $ngrams\n";
open(GR,"|$gzip -c >${sublm}.1gr.gz") || die "cannot create ${sublm}.1gr.gz\n";

while ($ng=<INP>){
  
  chop $ng; @ng=split(/[ \t]/,$ng); $ngcnt=(pop @ng) - $freqshift;
  
  if ($oldwrd ne $ng[0]){
    printf (GR "%s %s\n",$totcnt,$oldwrd) if $oldwrd ne '';
    $totcnt=0;$oldwrd=$ng[0];
  }
  
  #update counter
  $totcnt+=$ngcnt;
}

printf GR "%s %s\n",$totcnt,$oldwrd;
close(INP);
close(GR);

my (@h,$h,$hpr);    #n-gram history 
my (@dict,$code);   #sorted dictionary of history successors
my $diff;           #different successors of history
my $locfreq;        #accumulate frequency of n-grams of given size
my ($N1,$N2,$beta); #Kneser-Ney Smoothing: n-grams occurring once or twice 

warn "Computing n-gram probabilities:\n"; 

foreach ($n=2;$n<=$size;$n++){
  
  warn "$n-grams\n";
  open(HGR,"$gunzip -c ${sublm}.".($n-1)."gr.gz|") || die "cannot open ${sublm}.".($n-1)."gr.gz\n";
  open(INP,"$ngrams") || open(INP,"$ngrams|")  || die "cannot open $ngrams\n";
  open(GR,"|$gzip -c >${sublm}.${n}gr.gz");
  open(NHGR,"|$gzip -c > ${sublm}.".($n-1)."ngr.gz") || die "cannot open ${sublm}.".($n-1)."ngr.gz";

  chop($ng=<INP>); @ng=split(/[ \t]/,$ng);$ngcnt=(pop @ng) - $freqshift;
  chop($h=<HGR>);  @h=split(/ /,$h); $hpr=shift @h;
  
  $code=-1;@cnt=(); @dict=(); $totcnt=0;$diff=0; $oldwrd="";$N1=0;$N2=0;$locfreq=0;
   
  do{
    
#load all n-grams with prefix of history h, and collect useful statistics 
    
    while (join(" ",@h[0..$n-2]) eq join(" ",@ng[0..$n-2])) { #must be true the first time!   
      
      if ($oldwrd ne $ng[$n-1]) {
        $dict[++$code]=$oldwrd=$ng[$n-1];
        $diff++;
        $N1++ if $locfreq==1;
          $N2++ if $locfreq==2;
          $locfreq=$ngcnt;
      } else {
        $locfreq+=$ngcnt;
      }
        
        $cnt[$code]+=$ngcnt; $totcnt+=$ngcnt;           
        
        chop($ng=<INP>); @ng=split(/[ \t]/,$ng);$ngcnt=(pop @ng) - $freqshift;	
    }
      
#compute smothing statistics         
      
      if ($kneser_ney) {
        if ($N1==0 || $N2==0) {
          warn "Error in Kneser-Ney smoothing N1 $N1 N2 $N2 diff $diff: resorting to Witten-Bell\n";
          $beta=0;  
        } else {
          $beta=$N1/($N1 + 2 * $N2); 
        }
      }
      
#print smoothed probabilities
      
      my $boprob=0; #accumulate pruned probabilities 
      my $prob=0;
      
      for (my $c=0;$c<=$code;$c++) {
        
        if ($kneser_ney && $beta>0) {
          $prob=($cnt[$c]-$beta)/$totcnt;
        } else {
          $prob=$cnt[$c]/($totcnt+$diff);
        }

        $ngram=join(" ",@h[0..$n-2],$dict[$c]);
        
        #rm singleton n-grams 
        #rm n-grams containing cross-sentence boundaries
        #rm n-grams containing <unk> except for 1-grams
        if (($prune_singletons && $n>=3 && $cnt[$c]==1) ||
            (!$cross_sentence && $n >1 && &CrossSentence($size,$n,$ngram)) ||
            (($dict[$c]  eq '<unk>') || ($n>=2 && $h=~/<unk>/)) 
            ){	
         
          $boprob+=$prob;
          
          if ($n<$size) {	#output as it will be an history for n+1 
            printf GR "%f %s %s\n",-10000,join(" ",@h[0..$n-2]),$dict[$c];
          }
          
        } else { # print ngrams of highest level
          printf(GR "%f %s %s\n",log($prob)/$log10,join(" ",@h[0..$n-2]),$dict[$c]);
        }
      }
      
#rewrite history including back-off weight      
      
      print "$h - $ng - $totcnt $diff \n" if $totcnt+$diff==0;
        
#check if history has to be pruned out
        if ($hpr==-10000) {
        #skip this history
        } elsif ($kneser_ney && $beta>0) {
          printf NHGR "%s %f\n",$h,log($boprob+($beta * ($diff-$N1)/$totcnt))/$log10;
        } else {
          printf NHGR "%s %f\n",$h,log($boprob+($diff/($totcnt+$diff)))/$log10;
        }     
      
#reset smoothing statistics
      
      $code=-1;@cnt=(); @dict=(); $totcnt=0;$diff=0;$oldwrd="";$N1=0;$N2=0;$locfreq=0;
      
#read next history
      
      chop($h=<HGR>);  @h=split(/ /,$h); $hpr=shift @h;
      
  }until ($ng eq "");		#n-grams are over

 close(HGR); close(INP);close(GR);close(NGR);
 rename("${sublm}.".($n-1)."ngr.gz","${sublm}.".($n-1)."gr.gz");
}   


#check if n-gram contains cross-sentence boundaries
#<s> must occur only in first place
#</s> must only occur at last place


sub CrossSentence($size,$n,$ngram){
  
# warn "check CrossSentence $size $n |$ngram|\n";
  if (($ngram=~/ <s>/i) || 
      ($ngram=~/<\/s> /i) || 
      ($size<$n && $ngram=~/<\/s>$/i)){ 
    #warn "delete $ngram\n";
    return 1;
  }
  return 0;
}
