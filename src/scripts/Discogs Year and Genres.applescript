-- Configuration
set InputDirectory to "/Users/jcreid/Downloads/music_test"
set DiscogsToken to "please_insert_your_own_API_key_here"
-- you can find your API key at https://www.discogs.com/settings/developers

to ExtractString(AllText, LeftEdge, RightEdge, nthValue)
	set saveTID to text item delimiters
	set text item delimiters to LeftEdge
	set SecondChunk to text item (1 + nthValue) of AllText
	set text item delimiters to RightEdge
	set ExtractedValue to text item 1 of SecondChunk
	set text item delimiters to saveTID
	return ExtractedValue
end ExtractString

on theSplit(theString, theDelimiter)
	set oldDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to theDelimiter
	set theArray to every text item of theString
	set AppleScript's text item delimiters to oldDelimiters
	return theArray
end theSplit

to replaceText(find, replace, subject)
	set prevTIDs to text item delimiters of AppleScript
	set text item delimiters of AppleScript to find
	set subject to text items of subject

	set text item delimiters of AppleScript to replace
	set subject to subject as text
	set text item delimiters of AppleScript to prevTIDs

	return subject
end replaceText

to QueryDiscogs(ArtistSong)
	set baseURL to "https://api.discogs.com/database/search?"
	set AdditionalFilters to "type=master&format_exact=Single"
	set AuthString to " -H \"Authorization: Discogs token=" & DiscogsToken & "\""
	set UserAgent to " --user-agent \"CertunaScript/0.1\""
	set QueryString to "q=" & replaceText(" ", "+", ArtistSong)
	set curl_command to "curl -s " & baseURL & QueryString & "&" & AdditionalFilters & AuthString & UserAgent
	set rawResponse to do shell script curl_command
	delay 0.3 -- do not remove, Discogs rate limits API requests to 60 per minute

	-- Parse JSON response using shell tools (jq)
	set parsed to do shell script ("echo '" & rawResponse & "' | jq -r '.results[" & "0" & "] | {title: .title, year: (.year // \"\"), genre: (.genres // [] | join(\", \")), style: (.styles // [] | join(\", \"))} | \"title: \" + .title + \", year: \" + .year + \", genre: [\" + .genre + \"], style: [\" + .style + \"]\"")
	set Title to my ExtractString(parsed, "title: ", ", ")
	set ReleaseYear to my ExtractString(parsed, "year: ", ", ")
	set Genres to my ExtractString(parsed, "genre: [", "],")
	set Styles to my ExtractString(parsed, "style: [", "],")

	return {Title, ReleaseYear, Genres, Styles}

end QueryDiscogs

to WriteTagsToFile(filePath, ReleaseYear, GenreStringToWrite, CommentText)
	set commands to ""
	if ReleaseYear is not "" then
		set commands to commands & "exiftool -overwrite_original -Year=" & ReleaseYear & " " & quoted form of filePath & " && "
	end if
	if GenreStringToWrite is not "" then
		set commands to commands & "exiftool -overwrite_original -Genre=" & GenreStringToWrite & " " & quoted form of filePath & " && "
	end if
	if CommentText is not "" then
		set commands to commands & "exiftool -overwrite_original -Comment=" & CommentText & " " & quoted form of filePath & " && "
	end if
	if commands is not "" then
		-- Remove trailing " && "
		set commands to characters 1 thru ((length of commands) - 4) of commands as text
		do shell script commands
	end if
end WriteTagsToFile

-- User configuration dialogs
set WriteMultipleGenres to true
set WriteYear to false
set WriteGenres to false
set ManualGenre to false

set Question to display dialog "Do you want to update Year, Genre or both?" buttons {"Year", "Genre", "Both"} default button 3
if button returned of Question is "Year" or button returned of Question is "Both" then
	set WriteYear to true
end if
if button returned of Question is "Genre" or button returned of Question is "Both" then
	set WriteGenres to true
	set Question to display dialog "Choose a Genre per song manually, write one Genre automatically, or write all (multiple) Genres?" buttons {"Choose Genre", "One Genre (Auto)", "Multiple Genres (Auto)"} default button 2
	if button returned of Question is not "Multiple Genres (Auto)" then
		set WriteMultipleGenres to false
	end if
	if button returned of Question is "Choose Genre" then
		set ManualGenre to true
	end if
end if

set Question to display dialog "Write the Discogs Artist - Title to the Comments field?" buttons {"Yes", "No"} default button 2
if button returned of Question is "Yes" then
	set WriteToComments to true
else
	set WriteToComments to false
end if

-- Process files from directory instead of Apple Music
set directoryPath to POSIX file InputDirectory
set fileItems to list folder directoryPath without invisibles

-- Filter to audio files only
set audioExtensions to {"mp3", "flac", "m4a", "ogg", "wav", "wma", "aiff", "aif"}
set audioFiles to {}
repeat with itemName in fileItems
	set fileExtension to my theSplit(itemName, ".")
	set ext to last item of fileExtension
	set extLower to my replaceText(ext, (my replaceText(ext, ext, (do shell script "echo " & quoted form of ext & " | tr A-Z a-z"))) as text, ext)
	repeat with audioExt in audioExtensions
		if (my replaceText(ext, ext, (do shell script "echo " & quoted form of ext & " | tr A-Z a-z"))) as text is audioExt then
			set end of audioFiles to itemName
			exit repeat
		end if
	end repeat
end repeat

set FilesCounter to 0
set TagsWrittenCounter to 0
set ErrorCounter to 0

repeat with fileName in audioFiles
	set FilesCounter to FilesCounter + 1
	set filePath to POSIX file (InputDirectory & "/" & fileName) as text
	try
		-- Extract artist and title from filename
		set nameParts to my theSplit(fileName, " - ")
		if (count of nameParts) >= 2 then
			set ArtistString to item 1 of nameParts
			set SongString to my replaceText(" (" & (item 2 of nameParts), "", (item 2 of nameParts))
		else
			set ArtistString to ""
			set SongString to my replaceText(".mp3", "", (my replaceText(".flac", "", (my replaceText(".m4a", "", (my replaceText(".ogg", "", fileName)))))))
		end if

		-- Clean up artist string
		set ArtistString to my replaceText("& ", "", ArtistString)
		try
			set ArtistString to first item of my theSplit(ArtistString, " ft ")
		end try

		-- Clean up song string
		set SongString to first item of my theSplit(SongString, " (")
		set SongString to first item of my theSplit(SongString, " [")

		set ArtistSong to ArtistString & " " & SongString

		set QueryAnswer to my QueryDiscogs(ArtistSong)
		set Title to item 1 of QueryAnswer
		set ReleaseYear to item 2 of QueryAnswer
		set ReleaseGenres to item 3 of QueryAnswer
		set ReleaseStyles to item 4 of QueryAnswer

		set ReleaseGenres to my replaceText(", ", ";", ReleaseGenres)
		set ReleaseStyles to my replaceText(", ", ";", ReleaseStyles)

		set ReleaseGenresStyles to ReleaseGenres
		if ReleaseStyles is not "" then
			set ReleaseGenresStyles to ReleaseGenresStyles & ";" & ReleaseStyles
		end if

		-- Determine genre to write
		set GenreStringToWrite to ""
		if ManualGenre is true then
			if ReleaseGenresStyles contains ";" then
				set GenreArray to my theSplit(ReleaseGenresStyles, ";")
			else
				set GenreArray to {ReleaseGenresStyles}
			end if
			if (count of GenreArray) is 1 then
				set GenreStringToWrite to item 1 of GenreArray
			else
				set DialogText to "Choose genre for " & ArtistString & " - " & SongString
				set buttonList to {}
				repeat with g in GenreArray
					set end of buttonList to g
				end repeat
				set end of buttonList to "Skip"
				set GenrePicker to display dialog DialogText buttons buttonList default button 2
				if button returned of GenrePicker is not "Skip" then
					set GenreStringToWrite to button returned of GenrePicker
				end if
			end if
		else
			if WriteMultipleGenres is false then
				if ReleaseStyles contains ";" then
					set GenreStringToWrite to first item of theSplit(ReleaseStyles, ";")
				else
					set GenreStringToWrite to ReleaseStyles
				end if
			else
				set GenreStringToWrite to ReleaseGenresStyles
			end if
		end if

		-- Build comment text
		set CommentText to ""
		if WriteToComments is true and Title is not "" then
			set CommentText to Title
		end if

		-- Write tags to file
		if ReleaseYear is not "" or GenreStringToWrite is not "" or CommentText is not "" then
			my WriteTagsToFile(filePath, ReleaseYear, GenreStringToWrite, CommentText)
			set TagsWrittenCounter to TagsWrittenCounter + 1
		end if

	on error errMsg
		set ErrorCounter to ErrorCounter + 1
	end try
end repeat

set DialogText to "Done: " & TagsWrittenCounter & " tags written" & return & "Errors: " & ErrorCounter & " of " & FilesCounter & " files"
display dialog DialogText buttons {"ok"} default button 1
