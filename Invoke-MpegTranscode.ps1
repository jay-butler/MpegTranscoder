# Uncomnt the following line and the final curly brace line if you want this to be a function
# Function Invoke-MpegTanscode {
<#
	.SYNOPSIS
	Transcode Plex DVR TS media files to H/265 M4V files.
	.DESCRIPTION
	This scrpt traverses a folder and its subfolders to find all TS files. It uses the Handbrake CLI to transcode the files into H.265 M4V files and relocates the originals to an archive folder.
	Log files are created at the beginning of each transcode. If multiple machines are transcoding, this prevents a file from being processed more than once.
	If the log file or the M4V file exists, the file will be skipped. This allows the process to be restartable.
	If a transcode fails, move the original media file back to its original location and delete the log file before restarting the script.
	System Requirements:
	  * Runs in PowerShell 6, 7 or Windows PowerShell 5. Runs on Windows, macOS or Linux.
	  * Requires HandBrake CLI to be installed.
	  * No third-party module dependencies.
	.NOTES
	Author: Jay Butler.
	Date: 27 September 2022
	.PARAMETER SourceFolder
	Folder where media files are stored. Function will recurse through all subfolders looking for media files mathing the pattern *.TS.
	.PARAMETER ArchiveFolder
	Folder where original media files are placed after transcode. Provides an easy way to purge the originals if the transcode succeeded and a safeguards original files if transcode failed. 
	.PARAMETER LogFolder
	Folder where log files are placed. The log files are flag files created at the beginning of the transcode process. If multiple machines are transcoding the same library, the presence of the log file will force the file to be skipped. 
	.EXAMPLE
	./Invoke-MpegTranscode.ps1 -LogFolder '/Volumes/MediaLibrary/Transcodes/Logs' -SourceFolder '/Volumes/MediaLibrary/Television' -ArchiveFolder '/Volumes/MediaLibrary/Transcodes/Archive' -Verbose -InformationAction Continue;
	.EXAMPLE
	./Invoke-MpegTranscode.ps1 -LogFolder '\\192.168.0.123\MediaLibrary\Transcodes\Logs' -SourceFolder '\\192.168.0.123\MediaLibrary\Television' -ArchiveFolder '\\192.168.0.123\MediaLibrary_2\Transcodes\Archive' -Verbose -InformationAction Continue;
#>
[CmdletBinding()]
param (
	[Parameter(Mandatory = $true)]
	[string]$SourceFolder = '\\192.168.0.123\MediaLibrary\Television',
	[Parameter(Mandatory = $true)]
	[string]$LogFolder = '\\192.168.0.123\MediaLibrary\Transcodes\Logs',
	[Parameter(Mandatory = $true)]
	[string]$ArchiveFolder = '\\192.168.0.123\MediaLibrary\Archive'
)

BEGIN {
	$PSBoundParameters.GetEnumerator() | ForEach-Object { Write-Verbose $_ };

	if ($PSVersionTable.Platform -eq 'Unix') {
		$Transcode = { param($in, $out) /Applications/HandBrakeCLI -o av_mp4 -e x265 --all-subtitles -O -i $in -o $out };
		# $Transcode = { param($in, $out) /Applications/HandBrakeCLI --preset-import-gui -Z "Apple 1080p60 Surround CC" -i $in -o $out };
		$Slash = '/';
	} else {
		$Transcode = { param($in, $out) C:\Progra~1\HandBrake\HandBrakeCLI.exe -o av_mp4 -e x265 --all-subtitles -O -i $in -o $out };
		# $Transcode = { param($in, $out) C:\Progra~1\HandBrake\HandBrakeCLI.exe --preset-import-gui -Z "Apple 1080p60 Surround CC" -i $in -o $out };
		$Slash = '\';
	}
	$SourceFolder = Join-Path -Path $SourceFolder -ChildPath $Slash;
	$LogFolder = Join-Path -Path $LogFolder -ChildPath $Slash;
	$HostName = ([System.Net.Dns]::GetHostName());
	$ProcessedFiles = @();

	Write-Information '';
	Write-Information '****************************************************';
	Write-Information '**********   Video TS to M4V Conversion   **********';
	Write-Information '****************************************************';
	Write-Information '';
	$StartMsg = ('>> Started at {0}' -f (Get-Date -UFormat '%Y-%m-%d %r'))
	Write-Information $StartMsg;
	
}
PROCESS {
	Write-Verbose ('Source Folder: {0}' -f $SourceFolder);
	Write-Verbose ('Log Folder: {0}' -f $LogFolder);

	# Find all TS files in teh media folder...
	$TS_Files = Get-ChildItem -Path $SourceFolder -Filter '*.ts' -Recurse | Sort-Object -Property FullName;
	Write-Information ('Found {0} TS files to process...' -f $TS_Files.Count);
	
	foreach ($thisFile IN $TS_Files) {
		Write-Information '';
		Write-Information ('Processing file {0}...' -f $thisFile.Name) -InformationAction Continue;
		$DestFile = $thisFile.DirectoryName + $Slash + $thisFile.BaseName + '.m4v';
		$LogFile = ($LogFolder + $thisFile.BaseName + '.txt');
		if (-not (Test-Path -Path $LogFile)) {
			# Create the flag/log file so other machine won't transcode the same file...
			New-Item -Path $LogFile -ItemType File -Force | Out-Null;
			Set-Content -Path $LogFile -Value ($HostName + '  ' + $DestFile);
			$SourceFile = $thisFile.FullName;
			# If the m4v already exists, skip this file...
			if (-not (Test-Path -Path $DestFile)) {
				$ProcessedFiles += ('Processed file: {0}' -f $thisFile.Name);
				Write-Information ('Destination file {0}' -f $DestFile) -InformationAction Continue;
				# Let's do it...
				Invoke-Command -ScriptBlock $Transcode -ArgumentList $SourceFile, $DestFile;

				# Archive the original file...
				if (Test-Path -Path $DestFile) {
					Write-Information ('Moving original TS file to archive.') -InformationAction Continue;
					Move-Item -Path $SourceFile -Destination $ArchiveFolder;
				} else {
					Write-Error ('Transcode failed. Leaving source TS file in place.') -ErrorAction Continue;
				}

				# Move the Plex DVR log files to archive too...
				$TsLog = (Join-Path -Path $thisFile.DirectoryName -ChildPath $thisFile.BaseName) + '.log';
				if (Test-Path -Path $TsLog) {
					Move-Item -Path $TsLog -Destination $ArchiveFolder;
				} else {
					Write-Information ('TS log file missing. No file to move.') -InformationAction Continue;
				}
			} else {
				$ProcessedFiles += ('Skipped file (m4v): {0}' -f $thisFile.Name);
				Write-Information 'Skipping, M4V file found...' -InformationAction Continue;
			}
		} else { 
			$ProcessedFiles += ('Skipped file (log): {0}' -f $thisFile.Name);
			Write-Information 'Skipping, log file found...' -InformationAction Continue;
		}
	}
	Write-Information '';
	Write-Information '----------   Summary   -------------------------------------------------';
	Write-Output $ProcessedFiles;
	Write-Information '----------   Summary   -------------------------------------------------';
	Write-Information $StartMsg;
	Write-Information ('>> Ended at {0}' -f (Get-Date -UFormat '%Y-%m-%d %r'));
}
# }