B4A=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=9.85
@EndOfDesignText@
#Region Shared Files
#Macro: Title, Code bundle, ide://run?File=%ADDITIONAL%\..\B4X\CodeBundle.jar&Args=%PROJECT_NAME%
#CustomBuildAction: folders ready, %WINDIR%\System32\Robocopy.exe,"..\..\Shared Files" "..\Files"
'Ctrl + click to sync files: ide://run?file=%WINDIR%\System32\Robocopy.exe&args=..\..\Shared+Files&args=..\Files&FilesSync=True
#End Region

Sub Class_Globals
	Private Root As B4XView
	Private xui As XUI
	Private Shell As Shell
    Private TabStrip1 As TabPane

	' Add Timer for background scanning
    Private ScanTimer As Timer
	
    'Scanner Tab
    Private txtRootPath As TextField
    Private btnBrowse As Button
    Private btnScan As Button
    Private btnCleanSelected As Button
    Private btnCleanAll As Button
    Private CustomListView1 As CustomListView
    Private lblTotalSize As Label
    Private lblFileCount As Label
	Private lblRecycleBinStatus As Label
    Private ProgressBar1 As ProgressBar
    
    'Settings Tab
	Private chkSelect As CheckBox
    Private chkAutoBackup As CheckBox
	Private chkObjects As CheckBox
	Private chkTemp As CheckBox
	Private chkWWW As CheckBox
	Private chkLogs As CheckBox
    Private txtFilePatterns As TextArea
    Private txtFolderPatterns As TextArea
    Private btnSaveSettings As Button
    Private btnDefaultSettings As Button
    
    'History Tab
    Private lstCleanHistory As ListView
    Private btnClearHistory As Button
    Private lblLastCleanup As Label
	
	'Variables
    Private tempFiles As List
    Private totalBytes As Long
    'Private settings As Map
    'Private historyList As List
    
    Private scanning As Boolean
    Private cleaning As Boolean
	
    'Recycle Bin settings
    Private chkUseRecycleBin As CheckBox
    'Private chkDeletePermanently As CheckBox	
	Private chkKeepIcon As CheckBox
	Private chkKeepJson As CheckBox
	Private chkKeepGit As CheckBox
	
	Private lblName As Label
	Private lblPath As Label
	Private lblSize As Label
	Private lblType As Label
End Sub

Public Sub Initialize
'	B4XPages.GetManager.LogEvents = True
End Sub

'This event will be called once, before the page becomes visible.
Private Sub B4XPage_Created (Root1 As B4XView)
	Root = Root1
	Root.LoadLayout("MainPage")
    B4XPages.SetTitle(Me, "B4X Projects Cleaner")
	
    ' Initialize Timer
    ScanTimer.Initialize("ScanTimer", 100)
    ScanTimer.Enabled = False
	
    'Load Tabs
	TabStrip1.LoadLayout("Scanner", "Scanner")
	TabStrip1.LoadLayout("Settings", "Settings")
    TabStrip1.LoadLayout("History", "History")
	
    'Initialize lists
    tempFiles = CreateList

	'Set initial values
    txtRootPath.Text = GetDefaultProjectPath
    ProgressBar1.Visible = False
    UpdateStats(0, 0)
	
	'Load settings and history
	LoadSettingsToUI
	LoadHistoryToUI
	
    'Update Recycle Bin status
    UpdateRecycleBinStatus
End Sub

Sub CreateList As List
    Dim lst As List
    lst.Initialize
    Return lst
End Sub

Sub CreateFileInfo (Name As String, Folder As String, FileType As String, FileSize As Long, Selected As Boolean) As FileInfo
	Dim t1 As FileInfo
	t1.Initialize
	t1.Name = Name
	t1.Folder = Folder
	t1.FileType = FileType
	t1.FileSize = FileSize
	t1.Selected = Selected
	Return t1
End Sub

Sub GetDefaultProjectPath As String
    Dim path As String
    path = File.DirApp
    'Go up one level from current app directory
    Dim parent As String = File.GetFileParent(path)
    Return parent
End Sub

Sub btnBrowse_Click
    Dim fc As FileChooser
    fc.Initialize
    fc.InitialDirectory = txtRootPath.Text
    fc.Title = "Select B4X Projects Root Folder"
    'fc.SetExtensionFilter("All Folders", Array As String("*"))
    Dim selected As String = fc.ShowOpen(B4XPages.GetNativeParent(Me))
    If selected <> "" Then
        txtRootPath.Text = File.GetFileParent(selected)
    End If
End Sub

Sub btnScan_Click
    If scanning Then Return
    If txtRootPath.Text = "" Then
        xui.MsgboxAsync("Please select a root folder", "Error")
        Return
    End If
    
    'Reset
    tempFiles.Clear
    totalBytes = 0
    CustomListView1.Clear
    ProgressBar1.Visible = True
    ProgressBar1.Progress = -1 ' Indeterminate mode
    btnScan.Enabled = False
    btnScan.Text = "Scanning..."
    scanning = True
    
    ' Use a timer to start scanning in background
    ScanTimer.Enabled = True
End Sub

Sub ScanTimer_Tick
    ScanTimer.Enabled = False
    
    ' Scan in background
    Dim RootPath As String = txtRootPath.Text
    Dim filesList As List
    filesList.Initialize
    Dim total(1) As Long
    total(0) = 0
	
    ' Perform the actual scanning
    ScanFolderBackground(RootPath, filesList, total)
    
    ' Update UI on main thread
    tempFiles = filesList
    totalBytes = total(0)
    CallSubDelayed(Me, "UpdateScanResults")
End Sub

Sub ScanFolderBackground (Folder As String, filesList As List, total() As Long)
	If File.IsDirectory(Folder, "") = False Then Return
    
	'Check if this is a B4X project folder
	If IsB4XProjectFolder(Folder) Then
		'Scan for temp files in this project
		ScanProjectFolderBackground(Folder, filesList, total)
	End If
	
	'Recursively scan subfolders
	Dim subfolders As List = File.ListFiles(Folder)
	For Each subfolder As String In subfolders
		Dim fullPath As String = File.Combine(Folder, subfolder)
		'Log($" ${Folder} \ ${subfolder} "$)
		If File.IsDirectory(Folder, subfolder) Then
			

			If subfolder.EqualsIgnoreCase("drawable") Then
				Dim KeepIcon As Boolean = chkKeepIcon.Checked
				If KeepIcon And HasLargeIcon(fullPath) Then
					LogColor("Skipping B4A drawable folder with custom icon: " & fullPath, xui.Color_Blue)
					' remove res and Objects from List
					For i = 0 To filesList.Size - 1
						Dim FolderParent As String = File.GetFileParent(Folder)
						Dim fileMap As Map = filesList.Get(i)
						'Log(fileMap.Get("Path"))
						If fileMap.Get("Path") = FolderParent Then
							filesList.RemoveAt(i)
							LogColor("Objects folder exempted", xui.Color_Blue)
							Exit
						End If
					Next
					For i = 0 To filesList.Size - 1
						Dim fileMap As Map = filesList.Get(i)
						'Log(fileMap.Get("Path"))
						If fileMap.Get("Path") = Folder Then
							filesList.RemoveAt(i)
							LogColor("res folder exempted", xui.Color_Blue)
							Exit
						End If
					Next
					
'					Dim resIndex As Int = filesList.IndexOf(Folder)
'					If resIndex > -1 Then
'						filesList.RemoveAt(resIndex)
'						LogColor("res folder exempted", xui.Color_Blue)
'					End If
'					Dim FolderParent As String = File.GetFileParent(Folder)
'					Dim ObjectsIndex As Int = filesList.IndexOf(FolderParent)
'					If ObjectsIndex > -1 Then
'						filesList.RemoveAt(ObjectsIndex)
'						LogColor("Objects folder exempted", xui.Color_Blue)
'					End If
					Continue
				Else
					' Add for cleanup
					AddToResults(fullPath, "Folder", filesList, total)
					Log("B4A drawable folder without custom icon will be cleaned: " & fullPath)
				End If
				
				'Dim parent As String = File.GetFileParent(fullPath)
				'Log($" ${fileName} / ${File.GetName(parent)} "$)
'				If KeepIcon And File.GetName(Folder) = "B4A" And subfolder = "Objects" Then
'					Dim Objectssubfolders As List = File.ListFiles(fullPath)
'					Dim resIndex As Int = Objectssubfolders.IndexOf("res")
'					If resIndex > -1 Then
'						Dim resPath As String = File.Combine(fullPath, "res")
'						Dim ressubfolders As List = File.ListFiles(resPath)
'						Dim drawableIndex As Int = ressubfolders.IndexOf("drawable")
'						If drawableIndex > -1 Then
'							Dim resdrawablePath As String = File.Combine(resPath, "drawable")
'							If HasLargeIcon(resdrawablePath) Then
'								Log("Skipping B4A drawable folder with custom icon: " & fullPath)
'								Continue
'							Else
'								' Add for cleanup
'								AddToResults(fullPath, "Folder", filesList, total)
'								Log("B4A drawable folder without custom icon will be cleaned: " & fullPath)
'							End If
'						End If
'					End If
'				End If
			Else
				' Add for cleanup
				AddToResults(fullPath, "Folder", filesList, total)
			End If

			ScanFolderBackground(File.Combine(Folder, subfolder), filesList, total)
		End If
	Next
End Sub

Sub ScanProjectFolderBackground (ProjectFolder As String, filesList As List, total() As Long)
	Dim patterns As List = GetFilePatterns
	Dim folderPatterns As List = GetFolderPatterns
	'Dim KeepIcon As Boolean = chkKeepIcon.Checked
    
	'Scan for matching files
	Dim files As List = File.ListFiles(ProjectFolder)
	For Each fileName As String In files
		Dim fullPath As String = File.Combine(ProjectFolder, fileName)

		If File.IsDirectory(ProjectFolder, fileName) Then
			'Check if folder matches patterns
			If MatchesPattern(fileName, folderPatterns) Then
				' First check if this is a Git folder that should be excluded
				If IsGitRelatedFile(fileName, fullPath) And chkKeepGit.Checked Then
					Continue ' Skip this folder
				End If
				' Special handling for res/drawable folder
				
'				If KeepIcon And parent = "B4A" And fileName = "Objects" Then
'					
'					
				'
'					'Dim parent As String = File.GetFileParent(fullPath)
'					'If File.GetName(parent) = "res" Then
'					'	Dim grandParent As String = File.GetFileParent(parent)
'					'	If File.GetName(grandParent) = "Objects" Then
'					'		If HasLargeIcon(fullPath) = False Then
'					'			' Add the folder for cleanup
'					'			AddToResults(fullPath, "Folder", filesList, total)
'					'		End If
'					'		Continue ' Skip adding to list
'					'	End If
'					'End If
'				Else
'					' Normal folder handling
'					AddToResults(fullPath, "Folder", filesList, total)
'				End If
			End If
		Else
			'Check if file matches patterns AND is not excluded
			If MatchesPattern(fileName, patterns) Then
				' Check if we should exclude this file (e.g., JSON files)
				If ShouldExcludeFile(fileName, fullPath) = False Then
					AddToResults(fullPath, "File", filesList, total)
				End If
			End If
		End If
	Next
End Sub

Sub IsB4ADrawableFolder (FolderPath As String) As Boolean
    Try
        Dim folderName As String = File.GetName(FolderPath).ToLowerCase
        If folderName <> "drawable" Then Return False
        
        Dim parent As String = File.GetFileParent(FolderPath)
        Dim parentName As String = File.GetName(parent).ToLowerCase
        If parentName <> "res" Then Return False
        
        Dim grandParent As String = File.GetFileParent(parent)
        Dim grandParentName As String = File.GetName(grandParent).ToLowerCase
        If grandParentName <> "objects" Then Return False
        
        ' Check if this is a B4A project by looking for B4A project files
        Dim projectRoot As String = File.GetFileParent(grandParent)
        Dim projectFiles As List = File.ListFiles(projectRoot)
        For Each f As String In projectFiles
            If f.ToLowerCase.EndsWith(".b4a") Then
                Return True
            End If
        Next
        
        ' Also check for B4A project structure
        Dim objectsFiles As List = File.ListFiles(grandParent)
        For Each f As String In objectsFiles
            If f.ToLowerCase.Contains("b4a") Or f.ToLowerCase.Contains("android") Then
                Return True
            End If
        Next
    Catch
        ' If we can't check, assume it's not a B4A drawable folder
		Log(LastException)
    End Try
    Return False
End Sub

Sub AddToResults (Path As String, fileType As String, filesList As List, total() As Long)
    Try
        Dim size As Long
        If fileType = "File" Then
            size = File.Size(Path, "")
        Else
            size = CalculateFolderSize(Path)
        End If
        
        Dim fileMap As Map = CreateMap()
        fileMap.Put("Path", Path)
        fileMap.Put("Name", File.GetName(Path))
        fileMap.Put("Type", fileType)
        fileMap.Put("Size", size)
        fileMap.Put("Selected", True)
        fileMap.Put("Folder", File.GetFileParent(Path))
        
        filesList.Add(fileMap)
        total(0) = total(0) + size
    Catch
        Log("Error accessing: " & Path)
    End Try
End Sub

'Sub ScanFolder (Folder As String)
'    If File.IsDirectory(Folder, "") = False Then Return
'    
'    'Check if this is a B4X project folder
'    If IsB4XProjectFolder(Folder) Then
'        'Scan for temp files in this project
'        ScanProjectFolder(Folder)
'    End If
'    
'    'Recursively scan subfolders
'    Dim subfolders As List = File.ListFiles(Folder)
'    For Each subfolder As String In subfolders
'        Dim fullPath As String = File.Combine(Folder, subfolder)
'        If File.IsDirectory(fullPath, "") Then
'            ScanFolder(fullPath)
'        End If
'    Next
'End Sub

Sub IsB4XProjectFolder (Folder As String) As Boolean
    ' Check for B4X project files or project structure
    Dim files As List = File.ListFiles(Folder)
    For Each f As String In files
        ' Original B4X project files
        If f.EndsWith(".b4a") Or f.EndsWith(".b4i") Or f.EndsWith(".b4j") Or f.EndsWith(".b4r") Then
            Return True
        End If
        ' Check for project structure without extension
        'If f.ToLowerCase.Equals("project.txt") Or f.ToLowerCase.Equals("b4x.project") Then
        '    Return True
        'End If
        ' Check for common B4X project structure
        If File.IsDirectory(Folder, "Objects") Or _
           File.IsDirectory(Folder, "Files") Then
            Return True
        End If
    Next
    Return False
End Sub

'Sub ScanProjectFolder (ProjectFolder As String)
'	Dim patterns As List = GetFilePatterns
'	Dim folderPatterns As List = GetFolderPatterns
'	'Dim keepIcon As Boolean = chkKeepIcon.Checked
'    
'	'Scan for matching files
'	Dim files As List = File.ListFiles(ProjectFolder)
'	For Each fileName As String In files
'		Dim fullPath As String = File.Combine(ProjectFolder, fileName)
'        
'		Log(fileName)
'		
'		If File.IsDirectory(ProjectFolder, fileName) Then
'			'Check if folder matches patterns
'			If MatchesPattern(fileName, folderPatterns) Then
'				' First check if this is a Git folder that should be excluded
'				If IsGitRelatedFile(fileName, fullPath) And chkKeepGit.Checked Then
'					Continue ' Skip this folder
'				End If
'								
'				' Special handling for res/drawable folder in B4A Objects
'				If IsB4ADrawableFolder(fullPath) Then
'					If HasLargeIcon(fullPath) = False Then
'						AddTempFolder(fullPath, "Folder")
'						Log("B4A drawable folder without custom icon will be cleaned: " & fullPath)
'					Else
'						Log("Skipping B4A drawable folder with custom icon: " & fullPath)
'						Continue
'					End If
'					'Dim FolderOrFilesInsideObjects As List = File.ListFiles(fullPath)
'					'For Each FOF As String In FolderOrFilesInsideObjects
'					'	If File.GetName(FOF) = "res" And File.IsDirectory(FOF, "") Then
'					'		Dim grandParent As String = File.GetFileParent(FOF)
'					'		If File.GetName(grandParent) = "Objects" Then
'					'			' Check for custom icon > 8KB
'					'			If HasLargeIcon(fullPath) = False Then
'					'				AddTempFolder(fullPath, "Folder")
'					'			Else
'					'				Log("Skipping drawable folder with custom icon: " & fullPath)
'					'				Continue
'					'			End If
'					'		Else
'					'			AddTempFolder(fullPath, "Folder")
'					'		End If
'					'	Else
'					'		AddTempFolder(fullPath, "Folder")
'					'	End If
'					'Next
'					'Dim parent As String = File.GetFileParent(fullPath)
'
'				Else
'					' Add for cleanup
'					AddTempFolder(fullPath, "Folder")
'				End If
'			End If
'		Else
'			'Check if file matches patterns AND is not excluded
'			If MatchesPattern(fileName, patterns) Then
'				' Check if we should exclude this file (e.g., JSON files)
'				If ShouldExcludeFile(fileName, fullPath) = False Then
'					AddTempFile(fullPath, "File")
'				End If
'			End If
'		End If
'	Next
'End Sub

Sub HasLargeIcon (FolderPath As String) As Boolean
    ' Check if drawable folder contains icon files > 8KB
    Dim iconFiles As List = File.ListFiles(FolderPath)
    For Each iconFile As String In iconFiles
        Dim iconName As String = iconFile.ToLowerCase
        
        ' Check for common icon file names
        If iconName.Contains("icon") Or iconName.Contains("logo") Or _
           iconName.EndsWith(".png") Or iconName.EndsWith(".jpg") Or _
           iconName.EndsWith(".jpeg") Then
            
            Dim iconSize As Long = File.Size(FolderPath, iconFile)
            If iconSize > 8 * 1024 Then
				Log(iconFile & " will be excluded")
                Return True
            End If
        End If
    Next
    Return False
End Sub

Sub GetFilePatterns As List
    Dim patterns As List = CreateList
    
    'Default patterns for B4X temporary files
	'patterns.Add("*.java")
	'patterns.Add("*.class")
    
    'Add user patterns from settings
	Dim settings As Map = LoadSettings
    If settings.ContainsKey("FilePatterns") Then
        Dim userPatterns As String = settings.Get("FilePatterns")
        If userPatterns <> "" Then
            Dim userList As List = Regex.Split(CRLF, userPatterns)
            For Each p As String In userList
                If p.Trim <> "" Then patterns.Add(p.Trim)
            Next
        End If
    End If
    
    Return patterns
End Sub

Sub GetFolderPatterns As List
    Dim patterns As List = CreateList
    
    'Default folder patterns
    'patterns.Add("autobackups")
    'patterns.Add("objects")
    
    'Add user patterns from settings
	Dim settings As Map = LoadSettings
    If settings.ContainsKey("FolderPatterns") Then
        Dim userPatterns As String = settings.Get("FolderPatterns")
        If userPatterns <> "" Then
            Dim userList As List = Regex.Split(CRLF, userPatterns)
            For Each p As String In userList
                If p.Trim <> "" Then patterns.Add(p.Trim)
            Next
        End If
    End If
    
    Return patterns
End Sub

Sub MatchesPattern (FileName As String, Patterns As List) As Boolean
	' First check if this is a Git file that should be excluded
    If IsGitRelatedFile(FileName, "") And chkKeepGit.Checked Then
        Return False
    End If
	
    For Each pattern As String In Patterns
        If FileName.ToLowerCase = pattern.ToLowerCase Then Return True
        If pattern.Contains("*") Then
            Dim regexPattern As String = pattern.Replace(".", "\.").Replace("*", ".*")
            If Regex.IsMatch(regexPattern, FileName.ToLowerCase) Then Return True
        End If
    Next
    Return False
End Sub

Sub ShouldExcludeFile (FileName As String, FilePath As String) As Boolean
    ' Check if we should exclude JSON files
    If FileName.ToLowerCase.EndsWith(".json") Then
        ' Check if KeepJson is checked
        If chkKeepJson.Checked Then
            Return True ' Exclude this file
        End If
    End If

    ' Check if we should exclude Git/GitHub files
    If IsGitRelatedFile(FileName, FilePath) Then
        ' Check if KeepGit is checked
        If chkKeepGit.Checked Then
            Return True ' Exclude this file/folder
        End If
    End If
	
    ' Add other exclusion logic here if needed
    
    Return False ' Don't exclude
End Sub

Sub IsGitRelatedFile (FileName As String, FilePath As String) As Boolean
    Return IsGitFolderOrConfig(FileName, FilePath) Or IsLicenseFile(FileName)
End Sub

Sub IsGitFolderOrConfig (FileName As String, FilePath As String) As Boolean
    Dim nameLower As String = FileName.ToLowerCase
    
    ' Check for .git folder
    If nameLower = ".git" Then
        Return True
    End If
    
    ' Check for Git configuration files
    If nameLower = ".gitignore" Or nameLower = ".gitattributes" Or nameLower = ".gitmodules" Then
        Return True
    End If
    
    ' Check for GitHub specific files
    If nameLower = ".github" Then
        Return True
    End If
    
    ' Check for common Git files in folders
    Dim parentName As String = File.GetName(FilePath).ToLowerCase
    If parentName = ".git" Then
        Return True
    End If
    
    ' Check for Git-related files (like git config, hooks, etc.)
    Dim pathLower As String = FilePath.ToLowerCase
    If pathLower.Contains("/.git/") Or pathLower.Contains("\.git\") Then
        Return True
    End If
    
    Return False
End Sub

Sub IsLicenseFile (FileName As String) As Boolean
    ' Only check for license files when KeepGit is checked
    If Not(chkKeepGit.Checked) Then Return False
    
    Dim nameLower As String = FileName.ToLowerCase
    
    ' Exact matches
    If nameLower = "license" Or nameLower = "license.txt" Or nameLower = "license.md" Then
        Return True
    End If
    
    ' Files starting with "license."
    If nameLower.StartsWith("license.") Then
        Return True
    End If
    
    ' Files containing "license" with common extensions
    If nameLower.Contains("license") Then
        Dim ext As String = GetFileExtension(nameLower)
        Select Case ext
            Case "txt", "md", "rst", "html", "htm", "xml", "json"
                Return True
        End Select
    End If
    
    ' Common variations
    If nameLower = "copying" Or nameLower = "copying.txt" Or _
       nameLower = "copyright" Or nameLower = "copyright.txt" Or _
       nameLower = "authors" Or nameLower = "authors.txt" Or _
       nameLower = "contributors" Or nameLower = "contributors.txt" Or _
       nameLower = "notice" Or nameLower = "notice.txt" Then
        Return True
    End If
    
    ' Check for README files too (commonly included with licenses)
    If nameLower.StartsWith("readme") Then
        Return True
    End If
    
    Return False
End Sub

Sub GetFileExtension (FileName As String) As String
    Dim dotIndex As Int = FileName.LastIndexOf(".")
    If dotIndex > 0 Then
        Return FileName.SubString2(dotIndex + 1, FileName.Length).ToLowerCase
    End If
    Return ""
End Sub

'Sub AddTempFile (FilePath As String, FileType As String)
'    Try
'        Dim size As Long = File.Size(FilePath, "")
'        Dim fileMap As Map = CreateMap()
'        fileMap.Put("Path", FilePath)
'        fileMap.Put("Name", File.GetName(FilePath))
'        fileMap.Put("Type", FileType)
'        fileMap.Put("Size", size)
'        fileMap.Put("Selected", True)
'        fileMap.Put("Folder", File.GetFileParent(FilePath))
'        
'        tempFiles.Add(fileMap)
'        totalBytes = totalBytes + size
'        
'        'Update progress on UI thread occasionally
'        If tempFiles.Size Mod 5 = 0 Then
'            CallSubDelayed3(Me, "UpdateProgress", tempFiles.Size, totalBytes)
'        End If
'    Catch
'        Log("Error accessing file: " & FilePath)
'    End Try
'End Sub

'Sub AddTempFolder (FolderPath As String, FolderType As String)
'    Try
'        Dim size As Long = CalculateFolderSize(FolderPath)
'        Dim folderMap As Map = CreateMap()
'        folderMap.Put("Path", FolderPath)
'        folderMap.Put("Name", File.GetName(FolderPath))
'        folderMap.Put("Type", FolderType)
'        folderMap.Put("Size", size)
'        folderMap.Put("Selected", True)
'        folderMap.Put("Folder", File.GetFileParent(FolderPath))
'        
'        tempFiles.Add(folderMap)
'        totalBytes = totalBytes + size
'        
'        'Update progress
'        If tempFiles.Size Mod 5 = 0 Then
'            CallSubDelayed3(Me, "UpdateProgress", tempFiles.Size, totalBytes)
'        End If
'    Catch
'        Log("Error accessing folder: " & FolderPath)
'    End Try
'End Sub

Sub CalculateFolderSize (FolderPath As String) As Long
    Dim total As Long = 0
    Try
        Dim files As List = File.ListFiles(FolderPath)
        For Each f As String In files
            Dim fullPath As String = File.Combine(FolderPath, f)
            If File.IsDirectory(fullPath, "") Then
                total = total + CalculateFolderSize(fullPath)
            Else
                total = total + File.Size(fullPath, "")
            End If
        Next
    Catch
        'Ignore inaccessible folders
		Log(LastException)
    End Try
    Return total
End Sub

'Sub UpdateProgress (CurrentCount As Int, TotalSize As Long)
'    ' Update both progress and total size
'    If CurrentCount > 0 Then
'        lblTotalSize.Text = "Total Size: " & FormatFileSize(TotalSize)
'        lblFileCount.Text = "Files/Folders: " & CurrentCount
'    End If
'	
'	' You can also add a progress indicator if you want
'    ' For example, update a status label
'    ' lblStatus.Text = "Scanning... Found " & CurrentCount & " items"
'End Sub

Sub UpdateScanResults
    ProgressBar1.Visible = False
    ProgressBar1.Progress = 0
    btnScan.Enabled = True
    btnScan.Text = "Scan"
    scanning = False
    
    'Display results in CustomListView
    CustomListView1.Clear
    For Each fileMap As Map In tempFiles
        Dim info As FileInfo = CreateFileInfo(fileMap.Get("Name"), fileMap.Get("Folder"), fileMap.Get("Type"), fileMap.Get("Size"), fileMap.Get("Selected"))
        CustomListView1.Add(CreateListItem(info, CustomListView1.AsView.Width, 50dip), fileMap)
    Next
    
    UpdateStats(tempFiles.Size, totalBytes)
End Sub

Sub CreateListItem (f As FileInfo, Width As Int, Height As Int) As B4XView
	Dim p As B4XView = xui.CreatePanel("")
	p.LoadLayout("ItemLayout")
	p.SetLayoutAnimated(0, 0, 0, Width, Height)
	chkSelect.Checked = f.Selected
	lblName.Text = f.Name
	lblPath.Text = f.Folder
	Dim size As Long = f.FileSize
	lblSize.Text = FormatFileSize(size)
	lblType.Text = f.FileType
	Return p
End Sub

Sub UpdateStats(Count As Int, Size As Long)
    lblFileCount.Text = "Files/Folders: " & Count
    lblTotalSize.Text = "Total Size: " & FormatFileSize(Size)
End Sub

Sub FormatFileSize (Size As Long) As String
    If Size < 1024 Then
        Return NumberFormat2(Size, 0, 0, 0, False) & " B"
    Else If Size < 1024 * 1024 Then
        Return NumberFormat2(Size / 1024, 1, 0, 0, False) & " KB"
    Else If Size < 1024 * 1024 * 1024 Then
        Return NumberFormat2(Size / (1024 * 1024), 1, 0, 0, False) & " MB"
    Else
        Return NumberFormat2(Size / (1024 * 1024 * 1024), 1, 0, 0, False) & " GB"
    End If
End Sub

'Sub FileExistsSafe (Path As String) As Boolean
'    Try
'        Return File.Exists(Path, "")
'    Catch
'        Log("Error checking file existence: " & Path)
'        Return False
'    End Try
'End Sub
'
'Sub IsDirectorySafe (Path As String) As Boolean
'    Try
'        Return File.IsDirectory(Path, "")
'    Catch
'        Log("Error checking if path is directory: " & Path)
'        Return False
'    End Try
'End Sub

Sub LoadSettingsToUI
    Dim settings As Map = LoadSettings
    chkAutoBackup.Checked = settings.GetDefault("AutoBackup", True)
    chkObjects.Checked = settings.GetDefault("Objects", True)
    chkTemp.Checked = settings.GetDefault("temp", True)
    chkLogs.Checked = settings.GetDefault("logs", True)
    chkWWW.Checked = settings.GetDefault("www", True)
    chkUseRecycleBin.Checked = settings.GetDefault("UseRecycleBin", True)
    chkKeepIcon.Checked = settings.GetDefault("KeepIcon", True)
    chkKeepJson.Checked = settings.GetDefault("KeepJson", False)
	chkKeepGit.Checked = settings.GetDefault("KeepGit", False)
    'chkDeletePermanently.Checked = settings.GetDefault("DeletePermanently", False)
    txtFilePatterns.Text = settings.GetDefault("FilePatterns", GetDefaultFilePatterns)
    txtFolderPatterns.Text = settings.GetDefault("FolderPatterns", GetDefaultFolderPatterns)
End Sub

Sub GetDefaultFilePatterns As String
	Return $"*.class
*.java
*.log
*.txt
*.xml
*.dex
*.apk
*.jar
*.bak
*.backup"$
End Sub

Sub GetDefaultFolderPatterns As String
	Return $"autobackups
objects
b4xlibs
bin
dexed
gen
shell
src
temp
tmp
www
logs
.git"$
End Sub

Sub btnSaveSettings_Click
    'Save settings
    Dim settings As Map
    settings.Initialize
    settings.Put("AutoBackup", chkAutoBackup.Checked)
    settings.Put("Objects", chkObjects.Checked)
    settings.Put("logs", chkLogs.Checked)
    settings.Put("temp", chkTemp.Checked)
    settings.Put("www", chkWWW.Checked)
    settings.Put("UseRecycleBin", chkUseRecycleBin.Checked)
    'settings.Put("DeletePermanently", chkDeletePermanently.Checked)
	settings.Put("KeepIcon", chkKeepIcon.Checked)
	settings.Put("KeepJson", chkKeepJson.Checked)
	settings.Put("KeepGit", chkKeepGit.Checked)
    settings.Put("FilePatterns", txtFilePatterns.Text)
    settings.Put("FolderPatterns", txtFolderPatterns.Text)
    
    SaveSettings(settings)
	UpdateRecycleBinStatus
    xui.MsgboxAsync("Settings saved successfully", "Success")
End Sub

Sub btnDefaultSettings_Click
	Dim settings As Map
	settings.Initialize
    SaveSettings(settings)
    LoadSettingsToUI
	UpdateRecycleBinStatus
    xui.MsgboxAsync("Default settings restored", "Success")
End Sub

Sub UpdateRecycleBinStatus
    Dim statusText As String
    Dim statusColor As Int '= xui.Color_ARGB(255, 255, 0, 0) 'Red
    
    If chkUseRecycleBin.Checked Then
    	statusText = "Will move to Recycle Bin"
        statusColor = xui.Color_ARGB(255, 0, 128, 0) 'Green
    Else
        statusText = "WARNING: Files will be DELETED PERMANENTLY!"
        statusColor = xui.Color_ARGB(255, 255, 0, 0) 'Red
    End If
    
    lblRecycleBinStatus.Text = statusText
    lblRecycleBinStatus.As(B4XView).TextColor = statusColor
End Sub

Sub chkUseRecycleBin_CheckedChange (Checked As Boolean)
    UpdateRecycleBinStatus
End Sub

Sub btnCleanSelected_Click
	If cleaning Then Return
    If tempFiles.Size = 0 Then
        xui.MsgboxAsync("No files to clean. Please scan first.", "Info")
        Return
    End If
    
    Dim selectedCount As Int = GetSelectedCount
    If selectedCount = 0 Then
        xui.MsgboxAsync("No files selected. Please select files to clean.", "Info")
        Return
    End If
	
    Dim msg As String = "Are you sure you want to "
    If chkUseRecycleBin.Checked Then
        msg = msg & "move " & selectedCount & " items to Recycle Bin?"
    Else
        msg = msg & "PERMANENTLY delete " & selectedCount & " items?"
    End If

    xui.Msgbox2Async(msg, "Confirm Cleanup", "Yes", "", "No", Null)
    Wait For Msgbox_Result (Result As Int)
    If Result <> xui.DialogResponse_Positive Then Return

    'Start cleanup in background
    cleaning = True
    ProgressBar1.Visible = True
    ProgressBar1.Progress = 0
    btnCleanSelected.Enabled = False

	CleanupSelectedTask
End Sub

Sub btnCleanAll_Click
    'Select all items
    For Each fileMap As Map In tempFiles
        fileMap.Put("Selected", True)
    Next
    UpdateScanResults
    btnCleanSelected_Click
End Sub

Sub CleanupSelectedTask
	Dim count As Int = 0
	Dim totalSize As Long = 0
	Dim failed As List = CreateList
	Dim recycleBinFailed As List = CreateList
	Dim permanentDeleted As List = CreateList
    
	Dim totalSelected As Int = GetSelectedCount
	Dim processed As Int = 0
	Try
		For i = 0 To tempFiles.Size - 1
			Dim fileMap As Map = tempFiles.Get(i)
			If fileMap.Get("Selected") = True Then
				Dim path As String = fileMap.Get("Path")
				Dim fType As String = fileMap.Get("Type")
				Dim size As Long = fileMap.Get("Size")
            
				'Update progress
				processed = processed + 1
				CallSubDelayed3(Me, "UpdateCleanupProgress", processed, totalSelected)
            
				'Add a small delay between operations to prevent race conditions
				If processed > 1 Then
					Sleep(50) ' 50ms delay between operations
				End If
			
				'Move to Recycle Bin or delete
				Wait For (MoveToRecycleBinOrDelete(path, fType)) Complete (Success As Boolean)
				If Success Then
					count = count + 1
					totalSize = totalSize + size
                
					'Remove from list
					tempFiles.RemoveAt(i)
					i = i - 1
                
					'Check if it was deleted permanently
					If Not(chkUseRecycleBin.Checked) Then
						permanentDeleted.Add(path)
					End If
				Else
					failed.Add(path)
					'Check if Recycle Bin failed specifically
					If chkUseRecycleBin.Checked Then
						recycleBinFailed.Add(path)
					End If
				End If
			End If
		Next
	Catch
		Log(LastException)
		Return
	End Try
	
	'Update UI on main thread
	Dim results As Map = CreateMap()
	results.Put("Count", count)
	results.Put("TotalSize", totalSize)
	results.Put("Failed", failed)
	'results.Put("RecycleBinFailed", recycleBinFailed)
	results.Put("PermanentDeleted", permanentDeleted)
    
	CallSubDelayed2(Me, "UpdateCleanupResults", results)
End Sub

'Sub UpdateCleanupProgress (Current As Int, Total As Int)
'    If Total > 0 Then
'        ProgressBar1.Progress = (Current / Total) * 100
'    End If
'End Sub

Sub UpdateCleanupProgress (Current As Int, Total As Int)
    If Total > 0 Then
        ProgressBar1.Progress = (Current / Total) * 100
        ' Update status label if you have one
        ' lblStatus.Text = "Cleaning: " & Current & " of " & Total
    End If
End Sub

Sub UpdateCleanupResults (Results As Map)
    ProgressBar1.Visible = False
    btnCleanSelected.Enabled = True
    cleaning = False
    
    Dim count As Int = Results.Get("Count")
    Dim totalSize As Long = Results.Get("TotalSize")
    Dim failed As List = Results.Get("Failed")
    'Dim recycleBinFailed As List = Results.Get("RecycleBinFailed")
    Dim permanentDeleted As List = Results.Get("PermanentDeleted")
    
    'Update UI
    UpdateScanResults
    
    'Save to history
    AddToHistory(count, totalSize)
    
    'Show results
    Dim msg As String = ""
    
    If chkUseRecycleBin.Checked Then
        msg = "Moved " & count & " items to Recycle Bin (" & FormatFileSize(totalSize) & ")"
        
		'If recycleBinFailed.Size > 0 Then
		'    msg = msg & CRLF & CRLF & "Recycle Bin failed for " & recycleBinFailed.Size & " items."
		'    If chkDeletePermanently.Checked Then
		'        msg = msg & " These were deleted permanently."
		'    Else
		'        msg = msg & " These were NOT deleted."
		'    End If
		'End If
    Else
        msg = "Permanently deleted " & count & " items (" & FormatFileSize(totalSize) & ")"
    End If
    
    If failed.Size > 0 Then
        msg = msg & CRLF & "Failed to process " & failed.Size & " items."
    End If
    
    'Show details if there were permanent deletions
    If permanentDeleted.Size > 0 Then
        msg = msg & CRLF & CRLF & "Note: " & permanentDeleted.Size & " items were deleted permanently."
    End If
    
    xui.MsgboxAsync(msg, "Cleanup Complete")
End Sub

Sub GetSelectedCount As Int
    Dim count As Int = 0
    For Each fileMap As Map In tempFiles
        If fileMap.Get("Selected") = True Then
            count = count + 1
        End If
    Next
    Return count
End Sub

Sub MoveToRecycleBinOrDelete (Path As String, fType As String) As ResumableSub
    If chkUseRecycleBin.Checked Then
		Log("Attempting to move to Recycle Bin: " & Path)
        'Wait For (MoveToRecycleBin(Path)) Complete (Success As Boolean)
        Wait For (MoveToRecycleBinWithRetry(Path, 3)) Complete (Success As Boolean)
		Return Success
    Else
		Log("Attempting to delete permanently: " & Path)
        Return DeletePermanently(Path, fType)
    End If
End Sub

Sub MoveToRecycleBin (FilePath As String) As ResumableSub
    Try
        ' First check if the file/folder exists
        If Not(File.Exists(FilePath, "")) Then
            Log("File doesn't exist, skipping: " & FilePath)
            Return False
        End If
        
        ' Check if we're on Windows
        Dim os As String = GetSystemProperty("os.name", "")
        If os.ToLowerCase.Contains("windows") Then
            ' Use Windows-specific Recycle Bin method
            Dim jo As JavaObject
            jo.InitializeStatic("java.awt.Desktop")
            Dim desktop As JavaObject = jo.RunMethodJO("getDesktop", Null)
            
            Dim jo2 As JavaObject
            jo2.InitializeNewInstance("java.io.File", Array(FilePath))
            
            desktop.RunMethod("moveToTrash", Array(jo2))
            Return True
        Else
            ' On non-Windows systems, delete permanently
            Log("Recycle Bin not supported on " & os & ". Deleting permanently.")
            Return DeletePermanently(FilePath, "File")
        End If
    Catch
        Log("Error moving to Recycle Bin: " & LastException.Message)
        Log("File path: " & FilePath)
        Return False
    End Try
End Sub

Sub MoveToRecycleBinWithRetry (FilePath As String, MaxRetries As Int) As ResumableSub
    Dim retryCount As Int = 0
    Dim success As Boolean = False
    
    Do While retryCount < MaxRetries And success = False
        Wait For (MoveToRecycleBin(FilePath)) Complete (result As Boolean)
        success = result
        
        If Not(success) Then
            retryCount = retryCount + 1
            If retryCount < MaxRetries Then
                Log("Retry " & retryCount & " for: " & FilePath)
                Sleep(100) ' Small delay before retry
            End If
        End If
    Loop
    
    Return success
End Sub

Sub DeletePermanently (Path As String, fType As String) As Boolean
    Try
        ' First check if the file/folder exists
        If File.Exists(Path, "") = False Then
            Log("File doesn't exist, skipping delete: " & Path)
            Return True ' Return true since there's nothing to delete
        End If
        
        If fType = "File" Then
            File.Delete(Path, "")
        Else
            DeleteFolderRecursive(Path)
        End If
        Return True
    Catch
        Log("Failed to delete: " & Path)
        Log("Error: " & LastException.Message)
        Return False
    End Try
End Sub

Sub DeleteFolderRecursive (FolderPath As String)
    Try
        ' Check if folder exists
        If Not(File.IsDirectory(FolderPath, "")) Then
            Log("Folder doesn't exist, skipping: " & FolderPath)
            Return
        End If
				
        Dim files As List = File.ListFiles(FolderPath)
        For Each f As String In files
            Dim fullPath As String = File.Combine(FolderPath, f)
            If File.IsDirectory(fullPath, "") Then
                DeleteFolderRecursive(fullPath)
            Else
                If File.Exists(fullPath, "") Then
                    File.Delete(fullPath, "")
                Else
                    Log("File doesn't exist, skipping: " & fullPath)
                End If				
            End If
        Next
 
        ' Delete the folder itself
        If File.Exists(FolderPath, "") Then
            File.Delete(FolderPath, "")
        End If		
    Catch
        Log("Error deleting folder: " & FolderPath)
		Log("Error details: " & LastException.Message)
    End Try
End Sub

Sub btnEmptyRecycleBin_Click
    xui.Msgbox2Async("This will empty the Recycle Bin for ALL files, not just B4X temp files." & CRLF & _
                    "Are you sure?", "Empty Recycle Bin", "Yes", "", "No", Null)
    Wait For Msgbox_Result (Result As Int)
    If Result <> xui.DialogResponse_Positive Then Return
    
    EmptyRecycleBin
End Sub

Sub EmptyRecycleBin
    Try
        Shell.Initialize("shell", "powershell", Array("-Command", "Clear-RecycleBin -Force -Confirm:$false"))
        Shell.Run(30000)
        Wait For Shell_ProcessCompleted (Success As Boolean, ExitCode As Int, StdOut As String, StdErr As String)
        
        If Success Then
            xui.MsgboxAsync("Recycle Bin emptied successfully", "Success")
        Else
            xui.MsgboxAsync("Failed to empty Recycle Bin", "Error")
        End If
    Catch
        xui.MsgboxAsync("Error emptying Recycle Bin: " & LastException.Message, "Error")
    End Try
End Sub

Sub LoadHistoryToUI
    lstCleanHistory.Items.Clear
    Dim historyList As List = LoadHistory
    For Each record As Map In historyList
        Dim dateStr As String = record.GetDefault("Date", "")
        Dim count As Int = record.GetDefault("Count", 0)
        Dim size As Long = record.GetDefault("Size", 0)
        
        Dim displayText As String = dateStr & " - " & count & " items (" & FormatFileSize(size) & ")"
        lstCleanHistory.Items.Add(displayText)
    Next
    
    If historyList.Size > 0 Then
        Dim last As Map = historyList.Get(historyList.Size - 1)
        lblLastCleanup.Text = "Last cleanup: " & last.Get("Date") & " (" & _
            FormatFileSize(last.Get("Size")) & ")"
    Else
        lblLastCleanup.Text = "Last cleanup: Never"
    End If
End Sub

Sub AddToHistory (Count As Int, Size As Long)
    Dim record As Map = CreateMap()
    record.Put("Date", DateTime.Date(DateTime.Now))
    record.Put("Time", DateTime.Time(DateTime.Now))
    record.Put("Count", Count)
    record.Put("Size", Size)
    record.Put("Path", txtRootPath.Text)
    
    Dim historyList As List = LoadHistory
    historyList.Add(record)
    
    'Keep only last 50 records
    If historyList.Size > 50 Then
        historyList.RemoveAt(0)
    End If
    
    SaveHistory(historyList)
    LoadHistoryToUI
End Sub

Sub btnClearHistory_Click
    Dim historyList As List
    historyList.Initialize
    SaveHistory(historyList)
    LoadHistoryToUI
End Sub

'===== Settings Persistence =====
Sub LoadSettings As Map
    If File.Exists(File.DirApp, "settings.dat") Then
        Try
            Dim ser As B4XSerializator
            Return ser.ConvertBytesToObject(File.ReadBytes(File.DirApp, "settings.dat"))
        Catch
            Log("Error loading settings")
        End Try
    End If
    Return CreateMap()
End Sub

Sub SaveSettings (settings As Map)
    Dim ser As B4XSerializator
    Dim bytes() As Byte = ser.ConvertObjectToBytes(settings)
    File.WriteBytes(File.DirApp, "settings.dat", bytes)
End Sub

Sub LoadHistory As List
    Dim historyFile As String = File.Combine(File.DirApp, "history.dat")
    If File.Exists(historyFile, "") Then
        Try
            Dim ser As B4XSerializator
            Return ser.ConvertBytesToObject(File.ReadBytes(historyFile, ""))
        Catch
            Log("Error loading history")
        End Try
    End If
    Return CreateList
End Sub

Sub SaveHistory(history As List)
    Dim ser As B4XSerializator
    Dim bytes() As Byte = ser.ConvertObjectToBytes(history)
    File.WriteBytes(File.DirApp, "history.dat", bytes)
End Sub