Param ( 
       [alias("nl")]
       [switch]
       $NoLinks,
       [alias("v")]
       [switch]
       $Verbose,
       [alias("m")]
       [switch]
       $MD5,
       [alias("f")]
       [switch]
       $Force,
       [alias("d")]
       [switch]
       $DryRun
      )
 
<# 
.SYNOPSIS
  Get-ChildItem -recurse | mupload [-NoLinks|nl] [-MD5|m] [-Verbose|v]
	[-DryRun|d] <basedirectory>
.DESCRIPTION
	Upload a Windows directory hierarchy to Joyent Manta
 
	Joyent Manta is a cloud-based object storage system, with an
	integrated compute cluster.  mupload uploads a directory
	hierarchy to a particular manta account.
 
	There is one required parameter, which is the base directory
	in the remote Manta system.  Those directories are of the form
	"/<accountname>/[stor|public]/<user-selectable-names>".  NOTE
	that these are forward slashes.
 
	mupload takes a piped tree of items, 
	from  Get-ChildItem -recurse (or use gci -recurse)
	and determines each item type.  
	   -If the item is a directory, it creates it on Manta.
	   -If the item is a file, it uploads it to Manta in the 
	    relative directory 

	The current working Windows directory is the relative 
	tree to upload, and it is appended to the Manta base directory 
	specified above.  
	
	e.g. if you are in
	c:\Users\Administrator, and you provide
	/benwen20131018/stor/windowsbak001 as the Manta base directory, 
	all files and paths relative to c:\Users\Administrator will 
	be uploaded relative to /benwen20131018/stor/windowsbak001
	with the necessary conversion of Windows \ to Unix / path
	separators.
 
	Using -Force does NOT delete existing Manta objects if there is 
	not a local file to overwrite it.
 
.PARAMETER
	-NoLinks | nl
	Ignore files that end in '.lnk', which are typically Windows soft
	links.
 
	-Verbose | v
	Provide more output.
 
	-MD5 | m
	Uses a local install of openssl to compute the md5 digest and
	use that to force server side validation that the file uploaded
	is identical. openssl must be installed and found in the PATH
	tested with: http://slproweb.com/download/Win64OpenSSL-1_0_1h.exe

 
	-Force | f
	Ignore existing Manta base directory checks.  Note that
	existing objects will be overwritten, but non-overlapping
	objects will still remain.
 
	-DryRun | d
	Show what commands would be run, but don't actually execute them.
	
 
.EXAMPLE
	gci -recurse | mupload /benwen/stor/windowsbackup001/
.NOTES
	Getting started with Joyent Manta: 
	1) Download and Install Node.js as all of the client tools are
	built on Node.js. http://nodejs.org/download/
	2) Run this in a Powershell propmt.  It installes the Node
	Package called "manta": npm install -g manta 
	3) Create a Joyent Cloud account at http://joyent.com
	4) Create a private / public ssh key pair using the Joyent web
	console (you should be prompted as you sign up to create and
	download a key.  Note that some versions of IE may not work
	properly here).  
	5) Put the private key in your Windows home directory in a
	folder called ".ssh", for example "/User/benwen/.ssh/ (the key
	file should be called simply "id_rsa" in that directory.
	6) Do the same with the public key, except it's named
	"id_rsa.pub".  Note that DSA keys don't work yet with Manta
	(as of 2013-Oct).
	7) Create these three environment variables: 
	$env:MANTA_USER = "benwen20131018"
	$env:MANTA_URL = "https://us-east.manta.joyent.com"
	$env:MANTA_KEY_ID = "11:de:e4:68:f1:b9:3c:1b:9a:9d:01:f5:8c:eb:b7:7c"
	(substituting your Joyent username for benwen20131018, and
	your key fingerprint (the 11:de:e4...) which can be found in
	the Joyent web console in the same place.  Click on the
	generated key to expand the field to show both the fingerprint
	and public key) 
	8) Run this command to test that Manta is working: "mls".
	If you don't get an error message you're good to go.  Visit:
	http://apidocs.joyent.com/manta for more information.  
	9) To make -m MD5 work, install OpenSSL
	http://slproweb.com/download/Win64OpenSSL-1_0_1e.exe and
	add the directory for openssl.exe to your PATH
 
	TODO: figure out how to display the help text in the right
	place. 
 
	TODO: what is this thing going to do with special characters
	like quotes, etc?
	
	TODO: Error checking try/catch look for ENOTFOUND - broken connection 
	      and ContentMD5MismatchError - set up retry...
	
	TODO: Check for object being overwritten better
	[Compare|c] compare only option to check stored value MD5
	with directory tree and report differences (missing files, bad MD5)
 
.LINK
	http://apidocs.joyent.com/manta
 
#>
 


function Manta-Exists ($mydir) {
         $mycmd = 'mls'
         $invokeme = "& $mycmd $mydir 2>&1"
         $console_out = invoke-expression $invokeme
         ## "Console: " + $console_out | echo
         $returnme = [string]::join("`r`n",$console_out)
         ## "Return: " + $returnme | echo
         if ($returnme -match '.*Error.*') {
            $False
         } else {
            $True
         }
}


 
## First, see if Manta node command mls installed, callable
$mlscmd = "mls"
if (!(Get-Command $mlscmd -errorAction SilentlyContinue)) {
 "Node.js Manta command mls is not found" | echo
 "Check your Node.js,  npm manta installations" | echo
 exit 1
} 

## Second, see if mls works with supplied account information
$mydir=""
if (Manta-Exists($mydir)) {
  "Manta connection seems ok." | echo
} else {
  "Manta not responding, check network with mls and check that your Manta" | echo
  "environment variables have proper values: MANTA_USR, MANTA_URL, MANTA_KEY_ID" | echo
  "SSH keys in place: id_rsa and id_rsa.pub downloaded from Joyent, placed in in $HOME/.ssh" | echo
  exit 2
}


## Third if MD5 - check to see if openssl is in the PATH
if ($MD5) {
  $openssl = "openssl"
  if (!(Get-Command $openssl -errorAction SilentlyContinue)) {
    "For MD5 validtation, openssl must be installed" | echo
    "Check your path" | echo
  exit 3
  }
}


if (!( $args[0] -match '.*/$')) {
   $base = $args[0] += "/"
} else {
   $base = $args[0] 
}
 
if ($Verbose) { "Basedir: " + $base | echo }

if (! $Force) {
        if (Manta-Exists($base)) {
      		"Manta directory " + $base + " not found OR already exists.  Aborting.  Use -Force to override." | echo
      		exit 4
        }
} else {
          $mcmd = "mmkdir"
          $mopts = "-p", $base
          if ($Verbose) { "Creating Manta base directory: " + $base | echo }
          if ($DryRun) {
                "Dry Run: " + $mcmd + " " + $mopts | echo
          } else {
            & $mcmd $mopts
          }
          $mcmd = ""
          $mopts = ""
}

 
foreach ($i in $input) {
	if ($Verbose) {"Processing: " +  $i.name + " is a container: " + $i.PSIsContainer | echo}
	$tmp = Resolve-Path -relative $i.fullname
	$tmp = $tmp -replace '\\', '/'
	$tmp = $tmp -replace '\./', ''
	$mdir = $base + $tmp
	if ($Verbose) {"manta path: " + $mdir | echo}
 
	
	if ($i.PSIsContainer) {
	   ## mmkdir -p makes parent directories if needed
	   $mcmd = "mmkdir"
	   $mopts = "-p", $mdir 
	} else {
	   ## Is this a soft link
	   if (($i.name -match '.*.lnk$') -and ($NoLinks)) {
	      ## do nothing
	      $mcmd = ""
	      $mopts = ""
		  $mdhr = ""
	   } else {
	   ## A regular file 
		  if ($i.Length -gt  5000000000) {
		    ## Set header to break 5Gb upload limit, pad size with 50Mb
			$mcmd = "mput"
			$size = $i.Length + 50000000
			$mhdr = " -H `"max-content-length: $size`" " 
			$mopts = "-f", $i.fullname, $mdir
			if ($Verbose) {$i.fullname + " Larger than 5Gb, using header: " + $mhdr | echo}
		  } else {
			$mhdr = " "
		        $mcmd = "mput"
		        $mopts = "-f", $i.fullname, $mdir
		  }
		  if ($MD5) {
			$digest = "dgst -md5 -binary -out digest.bin"
			$encrypt = "enc -base64 -in digest.bin"
			$fullname = $i.fullname
			$quote = '"'
			$opensslargs = $openssl + " " + $digest + " " + $quote + $fullname + $quote
			if ($DryRun) {
			   "Dry Run: " + "cmd /c" + " " + $opensslargs | echo
			}
			if ($Verbose) { echo $opensslargs }
			 ## PowerScript escape syntax - problems with 
			 ## spaces inside quotes inside file args for openssl
			 ## http://connect.microsoft.com/PowerShell/feedback/details/376207
			 ## So we run in command.com shell instead
			 & cmd /c $opensslargs
			 $opensslargs = $openssl + " " + $encrypt
			 if ($DryRun) {
			   "Dry Run: " + "cmd /c" + " " + $opensslargs | echo
			 }
			 if ($Verbose) { echo $opensslargs }
			 $md5string = & cmd /c $opensslargs
			 $md5HDR = "-H `"content-md5: $md5string`" "
			 & rm digest.bin
			 if ($DryRun) {
			   "Dry Run: " + $md5HDR | echo
			 }
		  } else {
		     $md5HDR = ""
		  }
	   }
	}
	
	if ($DryRun) { 
	   "Dry Run: " + $mcmd + " " + $mhdr + " " + $md5HDR + " " + $mopts | echo 
	} else { 
	   if ($Verbose) { 
	       $mcmd + $mhdr + $md5HDR + $mopts | echo 
	   } else {
	       if ($mcmd -match "mmkdir") {
	       	   # mmkdir is silent, provide feedback
		   $mcmd + $mhdr + $md5HDR + $mopts | echo 
	       }
	   }
	       	   
	   & $mcmd $mhdr $md5DHR $mopts
	}
 
}
