#!/usr/bin/perl
use warnings;
use strict;
use Data::Dumper;
use Scalar::Util qw(looks_like_number);
use Carp qw(confess carp croak cluck);
use Getopt::Long;
#      my $data   = "file.dat";
#      my $length = 24;
#      my $verbose;

my $opts;
%{$opts} = ('U'	=> './trimmedFq.fq.gz',
			'R1'=> './trimmedFq_1.fq.gz',
			'R2'=> './trimmedFq_2.fq.gz');

GetOptions ("read1|r1|1=s"   => \$opts -> {'R1'},      # string
	"read2|r2|2=s"   => \$opts -> {'R2'},
	"unpaired|un|U=s"   => \$opts -> {'U'},
	"samout|s=s"	=> \$opts -> {'s'}) or die("Error in command line arguments\n");

main();

sub main{
	#use:
	#paste \
	# <(bedtools intersect -wao -bed -a <(\
	#  samtools view -Sb 3294553_IN-14_1545_A1_1_simple.sam) \
	#  -b /groups/umcg-oncogenetics/tmp04/res/probe_ET1262F_2_182.ensembl.bed -S |\
	# perl tickerRefine.pl - ) <(grep -vP '^\@'  3294553_IN-14_1545_A1_1_simple.sam  ) |\
	# tickertape.pl
	#in one line:
	# paste <(bedtools intersect -wao -bed -a <(samtools view -Sb 3294553_IN-14_1545_A1_1_simple.sam) -b /groups/umcg-oncogenetics/tmp04/res/probe_ET1262F_2_182.ensembl.bed -S | perl tickerRefine.pl - ) <(grep -vP '^\@'  3294553_IN-14_1545_A1_1_simple.sam  ) | perl tickertape.pl 
	
	
	warn "Use:<-1 s1r1.fq.gz -2 s1r2.fq.gz -U s1.fq.gz> </dev/stdin> |<-s sam> </dev/stdin>  Commandline: $0 ".join(' ',@ARGV)."\n";
	
	my $recordLast;
	my $buffer;
	my $record;
	my $fqouthandles;
	my $samOutHandle;
	if($opts -> {'R2'} && $opts -> {'R1'}){
		my $cmd = "gzip -c > ".$opts -> {'R1'};
		open($fqouthandles -> [1],'|-',$cmd) or die "Cannot write '$cmd'";
		$cmd = "gzip -c > ".$opts -> {'R2'};
		open($fqouthandles -> [2],'|-',$cmd) or die "Cannot write '$cmd'";
	}
	if($opts -> {'U'}){
		my $cmd = "gzip -c > ".$opts -> {'U'};
		open($fqouthandles -> [0],'|-',$cmd) or die "Cannot write '$cmd'";
	}
	if($opts -> {'s'}){
		my $cmd = $opts -> {'s'};
		open($samOutHandle,'>',$cmd) or die "Cannot write '$cmd'";
	}
	my $probepemetrics;
	
	while(<>){
		$record = DumbReader($_);
		Validate($record);
		if(HasPairedEndTag($record)){
			my $r1 = $record;
			$_ = <>;
			my $r2 = DumbReader($_) or confess "Cannot read paired data although pe flags set";
			Validate($r2);
                        warn $0.Dumper($r1,$r2).$. if(GetNameRead($r1) =~  m/820/);

			if(my $fqs = TrimReadsByProbe($r1,$r2)){
				$probepemetrics = GetPeStats($r1,$r2);
				my @sams = TrimSamReadsByProbe($r1,$r2);
				#get a nice result dump
				#warn $0.Dumper($fqs,$r1,$r2).$.if(GetNameRead($r1) =~  m/820/);
				if(GetFqLength($fqs -> [0]) >=  20 && GetFqLength($fqs -> [1]) >= 20){
					if($opts -> {'s'}){
						print {$samOutHandle} SamAsString($sams[0]);
						print {$samOutHandle} SamAsString($sams[1]);
					}					
					if($opts -> {'R2'} && $opts -> {'R1'}){
						print {$fqouthandles -> [1]} WriteFastq($fqs -> [0]);
						print {$fqouthandles -> [2]} WriteFastq($fqs -> [1]);
						
					}else{
						print WriteFastqs($fqs);
					}
				}
			}
		}else{
                       #warn $0.Dumper($record).$. if(GetNameRead($record) =~  m/820/);

			if(my $fq = TrimReadByProbe($record)){
				my $sam = TrimSamReadByProbe($record);
				print {$samOutHandle} SamAsString($sam);
				#inpect record
				#warn $0.Dumper($fq,$record).$. if(GetNameRead($record) =~  m/820/);
				if(GetFqLength($fq) >= 10){
					#When printing the sam string the alignment could be any length becaus it does not need to be aligned again;
					print {$samOutHandle} SamAsString($sam);
					if(GetFqLength($fq) >= 20){
						print {$fqouthandles -> [0]} WriteFastq($fq);
					}
				}
			}
		}
		#confess "Is this PE?".Dumper($record).$!;
		#warn "While loop done";
		#die Dumper($record) if($. > 100);
	}
	warn "## $0 ## INFO: Done with $. lines processed"

}

#sub TrimSamReadsByProbe {
#	warn 'TrimSamReadsByProbe::'. Dumper(@_) if(GetNameProbe($_[0]) ne ".");
#	my ($r1, $r2)
#}
sub GetPeStats {
	warn 'GetPeStats::'. Dumper(@_) if(GetNameProbe($_[0]) ne ".");
}
sub TrimSamReadsByProbe{
	my $r1 = shift(@_);
	my $r2 = shift(@_);
	
	#calculate overlap if R2 has overlapping probe then limit then trim only if that on is present in R1
	
	my $fqs;
	#get the probe feature overlap (the amount of bases of that span the probe in genome space thus not accounting for IDSN cigars)
	my $overlapR2 = GetR2Overlap($r2);
	
	my $overlapR1;
	if($overlapR2 && $overlapR2 > 0){
		$overlapR1 = GetR1Overlap($r1,GetNameProbe($r2));
		
		#warn $overlapR1.Dumper($r1).GetNameProbe($r2);
	}
	#else{
	#	$overlapR1 = GetR1Overlap($r1);
	#}
	
	
	if(IsPrimaryAlignment($r1)> 0){#does this work??
		#r2
		#warn Dumper($overlapR2,$r2).$.;
		my $sam2 = GetSam($r2);
		if($overlapR2 && $overlapR2 > 0){
			#get the 			
			$sam2 = TrimSam($sam2,$overlapR2);
			#warn Dumper(\$overlapR2,\$trimOffsetR2,$r2);
			#die Dumper(\$overlap,$r,$fq);
		}
		
		#r1
		my $sam1 = GetSam($r1);
		if($overlapR1 && $overlapR1 > 0){
			
			$sam1 = TrimSam($sam1,$overlapR1);
			#die Dumper(\$overlap,$r,$fq);
		}
		
		#cluck "TrimReadsByProbe result:".Dumper($fqs);
		return ($sam1,$sam2);
	}else{
		return undef;
	}
}
sub TrimSamReadByProbe {
	my $r= shift(@_);
	my $sam;
	my $wiggle = 6;
	my $overlap = Get3PrimeOverlap($r);
	if(IsPrimaryAlignment($r)> 0){
		$sam = GetSam($r);
		
		#if(IsReverseAlignment($r)){
		#	$fq=ReverseComplementFq($fq);
		#}
		
		if($overlap){
			#my $trimOffset = CalcTrim($overlap, $r);
			#this here effects trimming parameters
			TrimSam($overlap, $sam);
			#confess Dumper(\$overlap,$r,$fq) if($. == 6);
		}
		return $sam;
	}else{
		
		return undef;
	}
	warn 'TrimSamReadByProbe::'. Dumper($r) if(GetNameProbe($r) ne ".");
}

sub EqualReadRecords{
	my $r=shift(@_);
	my $r2=shift(@_);
	if((GetChrRead($r) eq GetChrRead($r2)) 
		&& (GetStartRead($r) == GetStartRead($r2)) 
		&& (GetEndRead($r) == GetEndRead($r2)) 
		&& (GetNameRead($r) eq GetNameRead($r2)) 
		&& (GetStrandRead($r) eq GetStrandRead($r2))){
		return 1;
	}
	return 0;
}

sub Validate{
	my $r = shift(@_);
	my $n1 = GetHeaderRead($r);
	$n1 = substr($n1,0,-2) if(substr($n1,-2) eq '/1' || substr($n1,-2) eq '/2');
	die "## $0 ## Invalid record" . Dumper($r) if(not(GetH2($r) eq $n1));
}
sub GetChrRead{
	my $r=shift(@_);
	return($r -> [0]);# or die 'Record does not contain this many fields!'.Dumper($r);
}
sub GetStartRead{
	my $r=shift(@_);
	return($r -> [1]);# or die 'Record does not contain this many fields!'.Dumper($r);
}
sub GetEndRead{
	my $r=shift(@_);
	return($r -> [2]);# or die 'Record does not contain this many fields!'.Dumper($r);
}
sub GetNameRead{
	my $r=shift(@_);
	return($r -> [3]);# or die 'Record does not contain this many fields!'.Dumper($r);	
}
sub GetStrandRead{
	my $r=shift(@_);
	return($r -> [5]);# or die 'Record does not contain this many fields!'.Dumper($r);	
}
sub GetChrProbe{
	my $r=shift(@_);
	return($r -> [12]);# or die 'Record does not contain this many fields!'.Dumper($r);
}
sub GetStartProbe{
	my $r=shift(@_);
	return($r -> [13]);# or die 'Record does not contain this many fields!'.Dumper($r);
}
sub GetEndProbe{
	my $r=shift(@_);
	return($r -> [14]);# or die 'Record does not contain this many fields!'.Dumper($r);
}
sub GetNameProbe{
	my $r=shift(@_);
	if($r -> [0] eq "." || $r -> [1] == -1){
		return($r -> [16]);# or die 'Record does not contain this many fields!';
	}else{
		#warn $record -> [20];
		return($r -> [15]);# or die 'Record does not contain this many fields!';
	}
}
sub GetStrandProbe{
	my $r=shift(@_);
	return($r -> [17]);# or die 'Record does not contain this many fields!'.Dumper($r);	
}
sub TrimSam{
	my $trim = shift(@_);
	my $sam = shift(@_);
	my $cigarOld = GetSamCigarRead($sam); #for debugging stuff
	#right trim based on overlap
	my $cigar = CigarSamParser($sam);
	my $process_reverse = 0;
	$process_reverse++ if((IsReverseSamAlignment($sam) && not(HasPairedEndTag($sam))) ||
				(IsReverseSamAlignment($sam) && SamHasPairedEndTag($sam) && GetSamReadPairEnd($sam) == 1) ||
				(not(IsReverseSamAlignment($sam)) && (SamHasPairedEndTag($sam) && GetSamReadPairEnd($sam) == 2)));
	my $cigarNew;
	my $hardclip=$trim;
	#warn "Initial samrecord". Dumper($sam,$cigar, [$hardclip , $trim])." ";
	while(scalar(@{$cigar}) && $trim >= 0){
		my $ref;		
		if($process_reverse == 1){
			$ref = shift(@{$cigar});
		}else{
			$ref = pop(@{$cigar});
		}
		#do some calculations and set SamPos,SamCigar...to the correct positionsand hard clip when needed.
		my ($operation,$amount) = %$ref;
		my ($operationNew,$amountNew);	
		if($operation =~ /^[M\=X]$/){
			#eg 150M and trim 13
			if($trim-$amount>=0){#incomplete trim thus continues in the next operator(s).
				#TrimSamPos($process_reverse,$sam,$amount);
				$amountNew = 0;
				$operationNew = $operation;

				if($process_reverse){
					$sam = SetSamPosRead($sam,GetSamPosRead($sam) + $amount);
					$sam = SetSamSeqRead($sam,substr(GetSamSeqRead($sam),$amount));
					$sam = SetSamQualRead($sam,substr(GetSamQualRead($sam),$amount));
				}else{
					my $seq = GetSamSeqRead($sam);
					$sam = SetSamSeqRead($sam,substr($seq,0,length($seq) - $amount));
					my $qual = GetSamQualRead($sam);
					$sam = SetSamQualRead($sam,substr($qual,0,length($seq) - $amount));
				}
				$trim -= $amount;				
			}else{#Complete trim (does not continue in another operator)
				$amountNew = $amount - $trim;
				$operationNew = $operation;

				#$sam = SetSamPosRead($sam,GetSamPosRead($sam) + $trim) if($process_reverse);
				if($process_reverse){
					$sam = SetSamPosRead($sam,GetSamPosRead($sam) + $trim);
					$sam = SetSamSeqRead($sam,substr(GetSamSeqRead($sam),$trim));
					$sam = SetSamQualRead($sam,substr(GetSamQualRead($sam),$trim));
				}else{
					my $seq = GetSamSeqRead($sam);
					$sam = SetSamSeqRead($sam,substr($seq,0,length($seq) - $trim));
					my $qual = GetSamQualRead($sam);
					$sam = SetSamQualRead($sam,substr($qual,0,length($qual) - $trim));
				}
				$trim -= $amount;				
			}
			
		}elsif($operation =~ /^[IS]$/){
			#operation = insertion / soft clip
			#$trimbasesright += $amount;
			#pos does not change / trim does not change
			#cigar changes 
			#seq/qual changes
			#hardclip changes
			#No open insertion
			$amountNew = 0;
			$operationNew = $operation;
			$hardclip += $amount;
			if($process_reverse){

				$sam = SetSamSeqRead($sam,substr(GetSamSeqRead($sam) , $amount));
				$sam = SetSamQualRead($sam,substr(GetSamQualRead($sam) , $amount));
			}else{
				my $seq = GetSamSeqRead($sam);
				$sam = SetSamSeqRead($sam,substr($seq,0,length($seq) - $amount));
				my $qual = GetSamQualRead($sam);
				$sam = SetSamQualRead($sam,substr($qual,0,length($seq) - $amount));
			}
		}elsif($operation =~ /^[DN]$/){
			#operation  = deletion			
			#change pos 
			#change cigar
			#keep seq/qual
			#hardclip -= amount
			
			#no unaligned ends
			$amountNew = 0;
			$operationNew = $operation;
			if($process_reverse){
					$sam = SetSamPosRead($sam,GetSamPosRead($sam) + $amount);#so that we can remove the deletion
			}
			if($trim-$amount>=0){#incomplete trim thus continues in the next operator(s).			
				$hardclip -= $amount;
				$trim -= $amount;
			}else{#Complete trim (does not continue in another operator
				$hardclip -= $trim;
				$trim -= $amount;#so that we can remove the deletion
			}			

			
			#$overlap-=$amount;
		}elsif($operation =~ /^[HP]$/){
			die "Fatal Cigar operations \^[HP]\$ are not supported ".Dumper($sam,$cigar,\$trim,\$hardclip)." ";
		}

		#append to the new reduced cigar
		if($process_reverse == 1){
			#warn Dumper($sam,$cigar, [$operationNew, $amountNew, $hardclip , $trim])." ";
			my %h = ($operationNew=> $amountNew);		
			push(@{$cigarNew},\%h);
		}else{
			#warn Dumper($sam,$cigar, [$operationNew, $amountNew, $hardclip , $trim])." ";
			my %h = ($operationNew=> $amountNew);		
			unshift(@{$cigarNew},\%h);
		}
		#warn "temp SamRecord". Dumper($sam,$cigar, [$hardclip , $trim])." " if($cigarOld =~ m/S/);
		#die Dumper($ref,\$trim);
	}
	#merge the rest of the cigar
	if($process_reverse == 1){
		push(@{$cigarNew},@{$cigar});
		unshift(@{$cigarNew},{'H' => $hardclip});
	}else{
		unshift(@{$cigarNew},@{$cigar});
		push(@{$cigarNew},{'H' => $hardclip});
	}

	$sam = SetSamCigar($sam,CigarParsedAsString($cigarNew));
				
	#die "##record written" . Dumper($sam, \$cigar, \$cigarNew)."  " if($cigarOld =~ m/(\d+\w){4,}/ && IsReverseSamAlignment($sam) && $cigarOld =~ m/I/);#CigarParsedAsString($cigarNew) =~ m/S/, $cigarOld =~ m/S/, $cigarOld =~ m/(\d\w){4,}/, $cigarOld =~ m/(\d+\w){4,}/ && IsReverseSamAlignment($sam),
	#warn "##record written" . Dumper($sam, \$cigar, \$cigarNew)."  ";		
	#$fq->[1]=substr($fq->[1],0,length($fq->[1])-$trim);
	#$fq->[2]=substr($fq->[2],0,length($fq->[2])-$trim);
	
	return $sam;
}

sub SetSamCigar {
	my $s = shift @_;
	my $cigar = shift(@_);
	$s -> [5] = $cigar;
	return $s;
}

sub SamAsString {
	my $s = shift @_;
	my $string = join("\t",@{$s})."\n";
	return $string;
}
#port to sam
#while(scalar(@{$cigar}) && $overlap >= 0){#
#		#sam format spec: cigar should be read according to Read/and end of trimming (e.g. R1 trim endand R2 trim start) now also interprets SE as read1.
#		if(IsReverseAlignment($r) && not(HasPairedEndTag($r)) ||
#		 (IsReverseAlignment($r) && HasPairedEndTag($r) && GetReadPairEnd($r) == 1) ||
#		 (not(IsReverseAlignment($r)) && (HasPairedEndTag($r) && GetReadPairEnd($r) == 2))){
#			$ref = shift(@{$cigar});
#		}else{
#			$ref = pop(@{$cigar});
#		}
#		my $operation;
#		my $amount;
#		#warn "ref#overl".$ref.'#'.$overlap;
#		($operation,$amount) = %$ref;
#		#warn "TATATA".join("\t",($operation,$amount));
#		if($operation =~ /^[M\=X]$/){
#			if($overlap-$amount>=0){
#				$trimbasesright +=$amount;
#				$overlap-=$amount;
#			}else{
#				$trimbasesright +=$overlap;
#				$overlap-=$amount;
#			}
#			
#		}elsif($operation =~ /^[IS]$/){
#			$trimbasesright += $amount;
#		}elsif($operation =~ /^[D]$/){
#			#only reduce overlap not increment trimbases left
#			$overlap-=$amount;
#		}
#	}
sub IsReverseSamAlignment {
	my $s=shift(@_);
	
	if((GetSamFlagRead($s) & 16)){
		
		return 1;
	}else{
		#die Dumper($r) or die 'Record does not contain this many fields!'.Dumper($r);	
		return 0;
	}
}
sub SamHasPairedEndTag {
	my $s=shift(@_);
	
	if(defined(GetSamReadPairEnd($s))){
		
		return 1;
	}else{
		#die Dumper($r) or die 'Record does not contain this many fields!'.Dumper($r);	
		return 0;
	}
}
sub GetSamReadPairEnd {
	my $s=shift(@_);
	
	if((GetSamFlagRead($s) & 64 )){
		return 1;
	}elsif((GetSamFlagRead($s) & 128)){
		
		return 2;
	}else{
		#die Dumper($r) or die 'Record does not contain this many fields!'.Dumper($r);	
		return undef;
	}
}

sub GetSam {
	my $r = shift(@_);
	my $sam; 
	@{$sam}=(GetH2($r),		#0
		GetFlagRead($r),	#1
		GetChrRead($r),		#2
		GetPosRead($r),		#3
		GetMapqRead($r),	#4
		GetCigarRead($r),	#5
		GetRnextRead($r),	#6
		GetPnextRead($r),	#7
		GetTlenRead($r),	#8
		GetSeqRead($r),		#9
		GetQualRead($r),	#10
		GetOptionalFields($r) 	#11+
	);
	return $sam;
}

sub GetH2{
	my $record = shift(@_);
	#warn $record -> [19];
	if($record -> [0] eq "." || $record -> [1] == -1){
		return($record -> [20]);# or die 'Record does not contain this many fields!';
	}else{
		#warn $record -> [20];
		return($record -> [19]);# or die 'Record does not contain this many fields!';
	}
}
sub GetFlagRead{
	my $r=shift(@_);
	# $r -> [20]."\n".Dumper($r)."\nqual=".GetQualRead($r)."\nseq=".GetSeqRead($r) if(! looks_like_number($r -> [20]));
	my $ret;
	if($r -> [0] eq "." || $r -> [1] == -1){
		$ret = $r -> [21];# or die 'Record does not contain this many fields!';
	}else{

		$ret = $r -> [20];# or die 'Record does not contain this many fields!';
	}
	#
	defined($ret) or die "Invalid record at line ". $. .": ".Dumper($r);
	return($ret);
	#return($r -> [20]);# or die 'Record does not contain this many fields!'.Dumper($r);	
}
sub GetChromRead{
	my $r=shift(@_);
	# $r -> [20]."\n".Dumper($r)."\nqual=".GetQualRead($r)."\nseq=".GetSeqRead($r) if(! looks_like_number($r -> [20]));
	my $ret;
	if($r -> [0] eq "." || $r -> [1] == -1){
		$ret = $r -> [22];# or die 'Record does not contain this many fields!';
	}else{

		$ret = $r -> [21];# or die 'Record does not contain this many fields!';
	}
	#
	defined($ret) or die "Invalid record at line ". $. .": ".Dumper($r);
	return($ret);
	#return($r -> [20]);# or die 'Record does not contain this many fields!'.Dumper($r);	
}
sub GetPosRead{
	my $r=shift(@_);
	# $r -> [20]."\n".Dumper($r)."\nqual=".GetQualRead($r)."\nseq=".GetSeqRead($r) if(! looks_like_number($r -> [20]));
	my $ret;
	if($r -> [0] eq "." || $r -> [1] == -1){
		$ret = $r -> [23];# or die 'Record does not contain this many fields!';
	}else{

		$ret = $r -> [22];# or die 'Record does not contain this many fields!';
	}
	#
	defined($ret) or die "Invalid record at line ". $. .": ".Dumper($r);
	return($ret);
	#return($r -> [20]);# or die 'Record does not contain this many fields!'.Dumper($r);	
}
sub GetMapqRead{
	my $r=shift(@_);
	# $r -> [20]."\n".Dumper($r)."\nqual=".GetQualRead($r)."\nseq=".GetSeqRead($r) if(! looks_like_number($r -> [20]));
	my $ret;
	if($r -> [0] eq "." || $r -> [1] == -1){
		$ret = $r -> [24];# or die 'Record does not contain this many fields!';
	}else{

		$ret = $r -> [23];# or die 'Record does not contain this many fields!';
	}
	#
	defined($ret) or die "Invalid record at line ". $. .": ".Dumper($r);
	return($ret);
	#return($r -> [20]);# or die 'Record does not contain this many fields!'.Dumper($r);	
}
sub GetCigarRead{
	my $r=shift(@_);
	my $ret;
	if($r -> [0] eq "." || $r -> [1] == -1){
		$ret = $r -> [25];# or die 'Record does not contain this many fields!';
	}else{

		$ret = $r -> [24];# or die 'Record does not contain this many fields!';
	}
	#
	return($ret);
}

sub GetRnextRead{
	my $r=shift(@_);
	my $ret;
	if($r -> [0] eq "." || $r -> [1] == -1){
		$ret = $r -> [26];# or die 'Record does not contain this many fields!';
	}else{

		$ret = $r -> [25];# or die 'Record does not contain this many fields!';
	}
	#
	return($ret);
}
sub GetPnextRead{
	my $r=shift(@_);
	my $ret;
	if($r -> [0] eq "." || $r -> [1] == -1){
		$ret = $r -> [27];# or die 'Record does not contain this many fields!';
	}else{

		$ret = $r -> [26];# or die 'Record does not contain this many fields!';
	}
	#
	return($ret);
}
sub GetTlenRead{
	my $r=shift(@_);
	my $ret;
	if($r -> [0] eq "." || $r -> [1] == -1){
		$ret = $r -> [28];# or die 'Record does not contain this many fields!';
	}else{

		$ret = $r -> [27];# or die 'Record does not contain this many fields!';
	}
	#
	return($ret);
}
sub GetSeqRead{
	my $r=shift(@_);
	
	my $ret;
	if($r -> [0] eq "." || $r -> [1] == -1){
		$ret = $r -> [29];# or die 'Record does not contain this many fields!';
	}else{

		$ret = $r -> [28];# or die 'Record does not contain this many fields!';
	}
	#
	die $ret.Dumper($r)."$." if(!(defined($ret) && ($ret =~ /^[ATCGNatcgn]*$/)));
	return($ret);
	
	#return($r -> [28]);# or die 'Record does not contain this many fields!'.Dumper($r);	
}


sub GetQualRead{
	my $r=shift(@_);
	my $ret;
	if($r -> [0] eq "." || $r -> [1] == -1){
		$ret = $r -> [30];# or die 'Record does not contain this many fields!';
	}else{
		#warn $record -> [20];
		$ret = $r -> [29];# or die 'Record does not contain this many fields!';
	}
	return($ret);	
}
sub GetOptionalFields{
	my $r=shift(@_);
	my $ret;
	if($r -> [0] eq "." || $r -> [1] == -1){
		$ret = @{$r}[31..$#{$r}];# or die 'Record does not contain this many fields!';
	}else{
		#warn $record -> [20];
		$ret = @{$r}[30..$#{$r}];# or die 'Record does not contain this many fields!';
	}
	return($ret);	
}

sub IsPrimaryAlignment {
	my $r=shift(@_);
	#warn "test".(GetFlagRead($r) & 256);
	if((GetFlagRead($r) & 256)){
		
		return 0;
	}else{
		#die Dumper($r) or die 'Record does not contain this many fields!'.Dumper($r);	
		return 1;
	}
}
sub IsReverseAlignment {
	my $r=shift(@_);
	
	if((GetFlagRead($r) & 16)){
		
		return 1;
	}else{
		#die Dumper($r) or die 'Record does not contain this many fields!'.Dumper($r);	
		return 0;
	}
}
sub DumbReader{
	$_= shift(@_);
	chomp;
	my $record;
	@{$record}=split("\t");
	return $record;
}
sub Writer{
	$_= shift(@_);
	join("\t",@{$_})."\n";
}

sub GetHeaderRead{
	my $record = shift(@_);
	#warn $record -> [3];
	return($record -> [3]);# or die 'Record does not contain this many fields!'.Dumper($record);
}
sub RefineOverlapsBuffer {
	my $b = shift(@_);
	
	my $r1= shift(@{$b});
	if(scalar(@{$b}) > 0){
		while(my $r2= shift(@{$b})){
			$r1=GetBestOverlap($r1,$r2);
		}
	}
	push(@{$b},$r1);
	return $r1;
}
sub GetBestOverlap{
	my $r1= shift(@_);
	my $r2= shift(@_);
	
	#has two record or more:
	if(Get3PrimeOverlap($r1)<Get3PrimeOverlap($r2)){
		$r1=$r2;
	}
	#die Dumper($r1,$r2)."#";
	return $r1;
}

#notes for sub below
#'12',
#          '56493411',
#          '56493512',
#          'HISEQ-MFG:688:C7Y7WACXX_TCCAAT:1:1101:12442:2813',
#          '60',
#          '-',


#'12',
#          '56493381',
#          '56493431',
#          'ERBB3|NM_001982_exon_23_0_chr12_56493432_f_0_1937047',
#          '1',
#          '+',

#'12',
#          '56493507',
#          '56493557',
#          'ERBB3|NM_001982_exon_24_0_chr12_56493622_f_0_2022598',


#56493381	56493411			56493431	56493507	56493512	56493557
#|			|					|			|			|			|
#>>>>>>>>>>>>>>p1>>>>>>>>>>>>>>>>
#			<<<<<<<<<<<<<<<<<<<<<<read<<<<<<<<<<<<<<<<<<<
#											>>>>>>>>>>>>>>p2>>>>>>>>>
#
##has any 3p overlap -
#pend >= readstart + 1 
#pstart - wiggle <= readstart
#
#aka
#GetEndProbe($r) >= GetStartRead($r) + 1;
#GetStartProbe($r) - $wiggle <= GetStartRead($r);
#$overlap=GetEndProbe($r) - GetStartRead($r) + 1;
#56493381	56493411			56493431	56493507	56493512	56493557
#|			|					|			|			|			|
#<<<<<<<<<<<<<<p1<<<<<<<<<<<<<<<<
#			>>>>>>>>>>>>>>>>>>>>>>read>>>>>>>>>>>>>>>>>>>
#											<<<<<<<<<<<<<<p2<<<<<<<<<
#
##has any 3p overlap +
#pend + wiggle >= readend
#pstart + 1<= readend
#
#aka
#GetEndProbe($r) + $wiggle >= GetEndRead($r);
#GetStartProbe($r) +1 <= GetEndRead($r);
#$overlap=GetEndRead($r)-GetStartProbe($r) + 1;

sub Get3PrimeOverlap{
	my $r= shift(@_);
	my $overlap=0;
	my $wiggle = 5;
	
	if(	GetStrandRead($r) ne GetStrandProbe($r) 
		&& GetStrandRead($r) ne '.'
		&& GetStrandProbe($r) ne '.'){
		
		if(GetStrandRead($r) eq '+'
			&& GetEndProbe($r) + $wiggle >= GetEndRead($r)
			&& GetStartProbe($r) + 1 <= GetEndRead($r)){
				
			#--->read>
			#-----<probe<
			
			$overlap = GetEndRead($r) - GetStartProbe($r);
			#die Dumper(\$overlap,\$overlap,$r)."#";
		}elsif(GetStrandRead($r) eq '-'
			&& GetEndProbe($r) >= GetStartRead($r) + 1 
			&& GetStartProbe($r) - $wiggle <= GetStartRead($r)){
				
			#---<read<
			#->probe>
			
			$overlap = GetEndProbe($r) - GetStartRead($r);
			#die Dumper(\$overlap,\$overlap,$r);
		}
	}else{
		#warn Dumper($r, \$overlap);
		#die Dumper($r, \$overlap)."#" if($overlap < 0);
	}
	#warn Dumper($r, \$overlap)."#";
	#die Dumper($r, \$overlap)if($overlap > 0);
	
	return $overlap;
}

sub IsPairedEnd {
	return(HasPairedEndTag(@_));
}
sub HasPairedEndTag {
	my $r= shift(@_);
	#test
	my @rSplit=split('/',GetNameRead($r));
	if(scalar(@rSplit) > 1){;
		return(1);
	}else{
		return(0);
		
	}
}

sub TrimReadByProbe{
	my $r= shift(@_);
	my $fq;
	my $wiggle = 6;
	my $overlap = Get3PrimeOverlap($r);
	if(IsPrimaryAlignment($r)> 0){
		$fq->[0] = GetHeaderRead($r);
		$fq->[1] = GetSeqRead($r);
		$fq->[2] = GetQualRead($r);
		
		if(IsReverseAlignment($r)){
			$fq=ReverseComplementFq($fq);
		}
		
		if($overlap){
			my $trimOffset = CalcTrim($overlap,$r);
			#this here effects trimming parameters
			TrimFq($trimOffset,$fq);
			#confess Dumper(\$overlap,$r,$fq) if($. == 6);
		}
		return $fq;
	}else{
		return undef;
	}
}
sub TrimReadsByProbe{
	my $r1 = shift(@_);
	my $r2 = shift(@_);
	
	#calculate overlap if R2 has overlapping probe then limit then trim only if that on is present in R1
	
	my $fqs;
	my $overlapR2 = GetR2Overlap($r2);
	
	my $overlapR1;
	if($overlapR2 && $overlapR2 > 0){
		$overlapR1 = GetR1Overlap($r1,GetNameProbe($r2));
		
		#warn $overlapR1.Dumper($r1).GetNameProbe($r2);
	}
	#else{
	#	$overlapR1 = GetR1Overlap($r1);
	#}
	
	
	if(IsPrimaryAlignment($r1)> 0){#does this work??
		#r2
		$fqs->[1]->[0] = GetHeaderRead($r2);
		$fqs->[1]->[1] = GetSeqRead($r2);
		$fqs->[1]->[2] = GetQualRead($r2);
		
		if(IsReverseAlignment($r2)){
			$fqs->[1]=ReverseComplementFq($fqs->[1]);
		}
		
		#warn Dumper($overlapR2,$r2).$.;
		
		if($overlapR2 && $overlapR2 > 0){
			
			my $trimOffsetR2 = CalcTrim($overlapR2,$r2);
			#warn Dumper(\$overlapR2,\$trimOffsetR2,$r2);
			$fqs->[1]=ReverseComplementFq($fqs->[1]);
			TrimFq($trimOffsetR2,$fqs -> [1]);
			$fqs->[1]=ReverseComplementFq($fqs->[1]);
			
			#die Dumper(\$overlap,$r,$fq);
		}
		
		#r1
		$fqs->[0]->[0] = GetHeaderRead($r1);
		$fqs->[0]->[1] = GetSeqRead($r1);
		$fqs->[0]->[2] = GetQualRead($r1);
		
		if(IsReverseAlignment($r1)){
			$fqs->[0]=ReverseComplementFq($fqs->[0]);
		}
		
		if($overlapR1 && $overlapR1 > 0){
			my $trimOffsetR1 = CalcTrim($overlapR1,$r1);
			TrimFq($trimOffsetR1,$fqs -> [0]);
			#die Dumper(\$overlap,$r,$fq);
		}
		
		#cluck "TrimReadsByProbe result:".Dumper($fqs);
		return $fqs;
	}else{
		return undef;
	}
}
sub ReverseComplementFq {
	my $fq = shift(@_);
	
	$fq->[1] = reverse($fq->[1]);
	$fq->[1] =~ tr/ATCGNatcgn/TAGCNtagcn/;
	
	$fq->[2] = reverse($fq->[2]);
	
	return $fq;
}
sub TrimFq{
	my $trim = shift(@_);
	my $fq = shift(@_);
	
	$fq->[1]=substr($fq->[1],0,length($fq->[1])-$trim);
	
	$fq->[2]=substr($fq->[2],0,length($fq->[2])-$trim);
	
	return $fq;
}
sub CalcTrim{
	my $overlap = shift(@_);
	my $r= shift(@_);
	my $cigar;
	$cigar = CigarParser($r);
	my $trimbasesright=0;
	my $ref;
	#warn "####ref#overl".$ref.'#'.$overlap;
	
	#die id=zfsmsljhrbhfxkjzdhsbrvfkjhzkjhfxdzkjhbf
	#fix this should
	#die "[FATAL] $0::CalcTrim : DUMPER";
	
	while(scalar(@{$cigar}) && $overlap >= 0){
		#sam format spec: cigar should be read according to Read/and end of trimming (e.g. R1 trim endand R2 trim start) now also interprets SE as read1.
		if(IsReverseAlignment($r) && not(HasPairedEndTag($r))|| (IsReverseAlignment($r) && HasPairedEndTag($r) && GetReadPairEnd($r) == 1) || (not(IsReverseAlignment($r)) && (HasPairedEndTag($r) && GetReadPairEnd($r) == 2))){
			$ref = shift(@{$cigar});
		}else{
			$ref = pop(@{$cigar});
		}
		my $operation;
		my $amount;
		#warn "ref#overl".$ref.'#'.$overlap;
		($operation,$amount) = %$ref;
		#warn "TATATA".join("\t",($operation,$amount));
		if($operation =~ /^[M\=X]$/){
			if($overlap-$amount>=0){
				$trimbasesright +=$amount;
				$overlap-=$amount;
			}else{
				$trimbasesright +=$overlap;
				$overlap-=$amount;
			}
			
		}elsif($operation =~ /^[IS]$/){
			$trimbasesright += $amount;
		}elsif($operation =~ /^[D]$/){
			#only reduce overlap not increment trimbases left
			$overlap-=$amount;
		}
	}
	
	
	warn "Something strange is happening here".Dumper(\$overlap,\$trimbasesright,$r,$cigar) if(HasPairedEndTag($r) && GetReadPairEnd($r) == 2 && $overlap > length(GetSeqRead($r)));
	#die Dumper(\$overlap,\$trimbasesright,$r,$cigar)if(GetCigarRead($r) =~ /S|I/ && $. > 38);
	return $trimbasesright;
}
sub CigarParser {
	my $r= shift(@_);
	my $c;
	my $cigar;
	@{$c} = split(/([A-Z=])/,GetCigarRead($r));
	while(my $tag = shift(@{$c})){
		if(looks_like_number($tag)){
			my %h = (shift(@{$c}) => $tag);
			push(@{$cigar}, \%h);
		}else{
			my %h = ($tag => 1);
			push(@{$cigar}, \%h);
		}
	}
	return $cigar;
}

sub CigarSamParser {
	my $s= shift(@_);
	my $cigar;
	my $c;
	@{$c} = split(/([A-Z=])/,GetSamCigarRead($s));
	while(my $tag = shift(@{$c})){
		if(looks_like_number($tag)){
			my %h = (shift(@{$c}) => $tag);
			push(@{$cigar}, \%h);
		}else{
			my %h = ($tag => 1);
			push(@{$cigar}, \%h);
		}
	}
	return $cigar;
}

sub CigarParsedAsString {
	my $c = shift(@_);
	#warn "CigarDump".Dumper(\$c)."";
	my $string = '';
	while(my $operation = shift(@{$c})){
		my ($operator, $amount) = %{$operation};
		die "invalid thing".Dumper($operation) if(scalar(keys(%{$operation}))!=1);
		if($amount == 1 ){#best practice write as:
			$string .= $amount. $operator;
		}elsif($amount == 0 ){
			#ignore do not grow string
		}else{
			$string .= $amount. $operator;
		}
	}
	return $string;
}
sub GetSamCigarRead {
	my $s= shift(@_);
	#die $s -> [5];
	return $s -> [5];
}
sub GetSamFlagRead {
	my $s= shift(@_);
	#die $s -> [1];
	return $s -> [1];
}
sub GetSamPosRead {
	my $s= shift(@_);
	return $s -> [3];
}
sub SetSamPosRead {
	my $s= shift(@_);
	my $pos = shift(@_);
	$s -> [3] = $pos;
	return $s;
}
sub GetSamSeqRead {
	my $s= shift(@_);
	return $s -> [9];
}
sub SetSamSeqRead {
	my $s= shift(@_);
	my $seq = shift(@_);
	$s -> [9] = $seq;
	return $s;
}
sub GetSamQualRead {
	my $s= shift(@_);
	return $s -> [10];
}
sub SetSamQualRead {
	my $s= shift(@_);
	my $qual = shift(@_);
	$s -> [10] = $qual;
	return $s;
}
sub WriteFastq {
	#my $fqHandle = STDOUT;
	my $fq = shift @_;
	
	return "\@".$fq->[0]."\n".$fq->[1]."\n"."\+\n".$fq->[2]."\n";
	
	#print $fqHandle "\@".$fq->[0]."\n";
	#print $fqHandle $fq->[1]."\n";
	#print $fqHandle "\+\n";
	#print $fqHandle $fq->[2]."\n";
	
	#warn "\@".$fq->[0]."\n";
	#print $fqHandle $fq->[1]."\n";
	#print $fqHandle "\+\n";
	#print $fqHandle $fq->[2]."\n";
	#$fastq->[1]=$seq;
	#$fastq->[0]=$seqHeader;
	#$fastq->[2]=$qual;
}
sub WriteFastqs {
	#my $fqHandle = STDOUT;
	my $fqs = shift @_;
	my $fq1=$fqs-> [0];
	my $fq2=$fqs-> [1];
	
	return ("\@".$fq1->[0]."\n".$fq1->[1]."\n"."\+\n".$fq1->[2]."\n",
		"\@".$fq2->[0]."\n".$fq2->[1]."\n"."\+\n".$fq2->[2]."\n");
	
	#print $fqHandle "\@".$fq->[0]."\n";
	#print $fqHandle $fq->[1]."\n";
	#print $fqHandle "\+\n";
	#print $fqHandle $fq->[2]."\n";
	
	#warn "\@".$fq->[0]."\n";
	#print $fqHandle $fq->[1]."\n";
	#print $fqHandle "\+\n";
	#print $fqHandle $fq->[2]."\n";
	#$fastq->[1]=$seq;
	#$fastq->[0]=$seqHeader;
	#$fastq->[2]=$qual;
}
sub GetFqLength {
	my $fq = shift(@_);
	
	if(defined($fq->[1]) && defined($fq->[2]) &&(length($fq->[1]) == length($fq->[2]) || $fq->[2] eq '*'|| $fq->[2] eq '')){
		if($fq->[2] eq '*'||($fq->[2] eq '' && $fq->[1] ne '')){
			warn "[WARN] No fastq qualtities found! Defaulting to ascii '5'";
			$fq -> [2] = '5' x length($fq -> [1]);
		}
		return length($fq->[1]);
	}
	#else
	confess "[FATAL] inconsistent read/qual in 'getFqLength' while working on fq:".Dumper($fq);
}

sub GetR1Overlap{
	my $r= shift(@_);
	my $R2probe;
	$R2probe = shift @_ if(scalar(@_));
	my $overlap=0;
	my $wiggle = 6;
	
	if($R2probe && $R2probe ne GetNameProbe($r)){
		#warn "return 0";
		return 0;
	}
	
	if(	GetStrandRead($r) ne GetStrandProbe($r) 
		&& GetStrandRead($r) ne '.'
		&& GetStrandProbe($r) ne '.'){
		
		if(GetStrandRead($r) eq '+'
			&& GetStrandProbe($r) eq '-'
			&& GetEndProbe($r) + $wiggle >= GetEndRead($r)
			&& GetStartProbe($r) +1 <= GetEndRead($r)){
				
			#--->read>
			#-----<probe<
			
			$overlap = GetEndRead($r) - GetStartProbe($r);
			#die Dumper(\$overlap,\$overlap,$r)."#";
		}elsif(GetStrandRead($r) eq '-'
			&& GetStrandProbe($r) eq '+'
			&& GetEndProbe($r) >= GetStartRead($r) + 1 
			&& GetStartProbe($r) - $wiggle <= GetStartRead($r)){
				
			#---<read<
			#->probe>
			
			$overlap = GetEndProbe($r) - GetStartRead($r);
			#die Dumper(\$overlap,\$overlap,$r);
		}
	}else{
		#there should not be overlap here
		#warn Dumper($r, \$overlap);
		#die Dumper($r, \$overlap)."#" if($overlap > 41);
	}
	#warn "Is this an error? ".Dumper($r, \$overlap)."#" if(GetNameProbe($r) =~ m/M01785:319:000000000-APBEA:1:2106:24472:4693/);
	#die "plz check for errors:".Dumper($r, \$overlap)if($overlap > 46);
	
	return $overlap;
}

#
#has R2?
#find probeoverlap as in:
#	
sub GetR2Overlap{
	my $r= shift(@_);
	my $overlap=0;
	my $wiggleR2 = 6;
	
	
	#strands should be eq
	
	if(	GetStrandRead($r) eq GetStrandProbe($r) 
		&& GetStrandRead($r) ne '.'
		&& GetStrandProbe($r) ne '.'){
		
		#somethimes this is too complex to find a good solution as is. Because the cigar also effects the start and end points. And 
		#die "fix overlap"
		if(GetStrandRead($r) eq '+' &&
			(GetStartRead($r) - $wiggleR2  <= GetStartProbe($r) || 
			GetStartRead($r) + $wiggleR2  >= GetStartProbe($r)) &&
			GetEndRead($r) >= GetStartProbe($r) ){
			
			
			
			#--->--read-->
			#--- >probe>
			
			$overlap = GetEndProbe($r) - GetStartRead($r);
			#warn Dumper(\$overlap,\$overlap,$r)."#";
		}elsif(GetStrandRead($r) eq '-' &&
			GetStartRead($r) <= GetEndProbe($r) && 
			(GetEndRead($r) + $wiggleR2  >= GetEndProbe($r) || 
			GetEndRead($r) - $wiggleR2  <= GetEndProbe($r))){
				
			#---<read<---
			#--<probe<---
			
			$overlap = GetEndRead($r) - GetStartProbe($r);
			#die Dumper(\$overlap,\$overlap,$r) if($overlap > 41);
		}
	}else{
		#warn Dumper($r, \$overlap);
		#die Dumper($r, \$overlap)."#" if($overlap > 41);
	}
	#warn Dumper($r, \$overlap)."#";
	#die Dumper($r, \$overlap)if($overlap > 41);
	
	return $overlap;
}

sub GetReadPairEnd {
	my $r = shift(@_);
	my $readend;
	(undef,$readend) = split('/',GetNameRead($r));
	return($readend);
}
