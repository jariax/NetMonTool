Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Windows.Forms.DataVisualization

# =====================================================
# CONFIGURATION
# =====================================================
$Nodes = @(
    @{ ID = 1;  NodeName = "NODE_1";  IP = "100.64.0.5"  },
    @{ ID = 2;  NodeName = "NODE_2";  IP = "100.64.0.6"  },
    @{ ID = 3;  NodeName = "NODE_3";  IP = "100.64.0.13" },
    @{ ID = 4;  NodeName = "NODE_4";  IP = "100.64.0.14" },
    @{ ID = 5;  NodeName = "NODE_5";  IP = "100.64.0.16" },
    @{ ID = 6;  NodeName = "NODE_6";  IP = "100.64.0.10" },
    @{ ID = 7;  NodeName = "NODE_7";  IP = "100.64.0.3" },
    @{ ID = 8;  NodeName = "NODE_8";  IP = "100.64.0.20" },
    @{ ID = 9;  NodeName = "NODE_9";  IP = "100.64.0.19" },
    @{ ID = 10; NodeName = "NODE_10"; IP = "100.64.0.11" },
    @{ ID = 11; NodeName = "NODE_11"; IP = "100.64.0.15" },
    @{ ID = 12; NodeName = "NODE_12"; IP = "100.64.0.25" },
    @{ ID = 13; NodeName = "NODE_13"; IP = "100.64.0.17" },
    @{ ID = 14; NodeName = "NODE_14"; IP = "100.64.0.26" },
    @{ ID = 15; NodeName = "NODE_15"; IP = "100.64.0.18" }
)

$NodeColors = @{
    1="Red"; 2="Blue"; 3="Green"; 4="Orange"; 5="Purple";
    6="Brown"; 7="DarkCyan"; 8="DarkMagenta"; 9="Gold"; 10="DarkGreen";
    11="DarkBlue"; 12="DarkRed"; 13="Teal"; 14="DarkOrange"; 15="DarkViolet"
}

# =====================================================
# SHARED STATE (Synchronized Hashtable for Multithreading)
# =====================================================
$syncHash = [hashtable]::Synchronized(@{})
$syncHash.IsRunning = $true
$syncHash.Nodes = $Nodes
$syncHash.NodeData = [hashtable]::Synchronized(@{})

# Initialize data so charts don't crash before first ping finishes
foreach ($node in $Nodes) {
    $syncHash.NodeData[$node.ID] = [hashtable]::Synchronized(@{
        LatencyHistory = @(0,0,0,0,0,0,0,0,0,0)
    })
}

# =====================================================
# BACKGROUND RUNSPACE (Network Pinging)
# =====================================================
$runspace = [runspacefactory]::CreateRunspace()
$runspace.ApartmentState = "STA"
$runspace.ThreadOptions = "ReuseThread"
$runspace.Open()
$runspace.SessionStateProxy.SetVariable("syncHash", $syncHash)

$psCmd = [PowerShell]::Create().AddScript({
    $ping = New-Object System.Net.NetworkInformation.Ping
    $timeoutMs = 2500
    $historyLimit = 10

    while ($syncHash.IsRunning) {
        foreach ($node in $syncHash.Nodes) {
            $id = $node.ID
            $ip = $node.IP
            
            # Fetch current state arrays
            $latHistory = [System.Collections.ArrayList]::new()
            $latHistory.AddRange($syncHash.NodeData[$id].LatencyHistory)

            # Perform Ping
            try {
                $reply = $ping.Send($ip, $timeoutMs)
                if ($reply.Status -eq "Success") {
                    $null = $latHistory.Add([int]$reply.RoundtripTime)
                } else {
                    $null = $latHistory.Add(0) # 0 ms indicates a timeout/drop
                }
            } catch {
                $null = $latHistory.Add(0)
            }

            # Trim to history limit
            if ($latHistory.Count -gt $historyLimit) { $latHistory.RemoveAt(0) }

            # Update Shared State safely
            $syncHash.NodeData[$id].LatencyHistory = @($latHistory)
        }
        # Brief pause between full polling cycles
        Start-Sleep -Milliseconds 500
    }
    $ping.Dispose()
})
$psCmd.Runspace = $runspace
$asyncHandle = $psCmd.BeginInvoke()

# =====================================================
# GUI SETUP (Main Thread)
# =====================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Live Node Latency Monitor"
$form.Width = 1400
$form.Height = 700
$form.StartPosition = "CenterScreen"

# --- Latency Chart ---
$latencyChart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
$latencyChart.Dock = "Fill" # Takes up the entire window space smoothly
$latArea = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
$latArea.AxisY.Minimum = 0
$latArea.AxisY.Maximum = 2500
$latArea.AxisY.Title = "Latency (ms)"
$latArea.AxisX.Minimum = 0
$latArea.AxisX.Maximum = 9
$latArea.AxisX.Title = "History (Rolling)"
$latencyChart.ChartAreas.Add($latArea)
$form.Controls.Add($latencyChart)

# --- Legend ---
$latLegend = New-Object System.Windows.Forms.DataVisualization.Charting.Legend
$latLegend.Docking = "Right"

# Increase the font size here (Change 14 to 16 or 18 if you need it even bigger)
$latLegend.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)

$latencyChart.Legends.Add($latLegend)

# --- Initialize Series ONCE ---
foreach ($node in $Nodes) {
    $id = $node.ID
    $name = $node.NodeName
    $color = $NodeColors[$id]

    $latSeries = New-Object System.Windows.Forms.DataVisualization.Charting.Series
    $latSeries.Name = $name
    $latSeries.ChartType = "Line"
    
    # CHANGE THIS: Increase line thickness for TV/NOC screens
    $latSeries.BorderWidth = 5 
    
    $latSeries.Color = [System.Drawing.ColorTranslator]::FromHtml($color)
    $latencyChart.Series.Add($latSeries)
}
# =====================================================
# GUI REFRESH TIMER
# =====================================================
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000 # Updates view every 2 seconds

$timer.Add_Tick({
    foreach ($node in $Nodes) {
        $id = $node.ID
        $name = $node.NodeName

        # Fetch latest data from the background thread
        $latHistory = $syncHash.NodeData[$id].LatencyHistory

        # Update Latency Chart Points
        $latencyChart.Series[$name].Points.Clear()
        for ($i = 0; $i -lt $latHistory.Count; $i++) {
            $latencyChart.Series[$name].Points.AddXY($i, $latHistory[$i])
        }
    }
    
    $latencyChart.Invalidate()
})

# =====================================================
# CLEANUP & LAUNCH
# =====================================================
$form.Add_FormClosing({
    $timer.Stop()
    $syncHash.IsRunning = $false # Tell background thread to stop
    $psCmd.EndInvoke($asyncHandle)
    $psCmd.Dispose()
    $runspace.Close()
    $runspace.Dispose()
})

$timer.Start()
$form.ShowDialog()