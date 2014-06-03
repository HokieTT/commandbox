/**
*********************************************************************************
* Copyright Since 2005 ColdBox Platform by Ortus Solutions, Corp
* www.coldbox.org | www.ortussolutions.com
********************************************************************************
* @author Brad Wood, Luis Majano, Denny Valliant
* The CommandBox Shell Object that controls the shell
*/
component accessors="true" singleton {

	// DI
	property name="commandService" 		inject="CommandService";
	property name="readerFactory" 		inject="ReaderFactory";
	property name="print" 				inject="print";
	property name="CR" 					inject="CR";
	property name="formatterUtil" 		inject="Formatter";
	property name="logger" 				inject="logbox:logger:{this}";
	property name="fileSystem"			inject="fileSystem";

	/**
	* The java jline reader class.
	*/
	property name="reader";
	/**
	* The shell version number
	*/
	property name="version";
	/**
	* Bit that tells the shell to keep running
	*/
	property name="keepRunning" default="true" type="Boolean";
	/**
	* Bit that is used to reload the shell
	*/
	property name="reloadShell" default="false" type="Boolean";
	/**
	* The Current Working Directory
	*/
	property name="pwd";
	/**
	* The default shell prompt
	*/
	property name="shellPrompt";

	/**
	 * constructor
	 * @inStream.hint input stream if running externally
	 * @outputStream.hint output stream if running externally
	 * @userDir.hint The user directory
	 * @userDir.inject userDir
	 * @tempDir.hint The temp directory
	 * @tempDir.inject tempDir
 	**/
	function init( 
		any inStream, 
		any outputStream, 
		required string userDir,
		required string tempDir,
		boolean asyncLoad=true
	){

		// Version is stored in cli-build.xml. Build number is generated by Ant.
		// Both are replaced when CommandBox is built.
		variables.version = "@build.version@.@build.number@";
		// Init variables.
		variables.keepRunning 	= true;
		variables.reloadshell 	= false;
		variables.pwd 			= "";
		variables.reader 		= "";
		variables.shellPrompt 	= "";
		variables.userDir 	 	= arguments.userDir;
		variables.tempDir 		= arguments.tempDir;
		
		// Save these for onDIComplete()
		variables.initArgs = arguments;
		// Store incoming current directory
		variables.pwd 	 		= variables.userDir;
						
    	return this;
	}

	/**
	 * Finish configuring the shell
	 **/
	function onDIComplete() {
		// Create reader console and setup the default shell Prompt
		variables.reader 		= readerFactory.getInstance( argumentCollection = variables.initArgs  );
		variables.shellPrompt 	= print.green( "CommandBox> ");
		
		// Create temp dir & set
		setTempDir( variables.tempdir );
		
		// load commands
		if( variables.initArgs.asyncLoad ){
			thread name="commandbox.loadcommands"{
				variables.commandService.configure();
			}
		} else {
			variables.commandService.configure();
		}
	}

	/**
	 * Exists the shell
	 **/
	Shell function exit() {
    	variables.keepRunning = false;
		
		return this;
	}


	/**
	 * Sets reload flag, relaoded from shell.cfm
	 * @clear.hint clears the screen after reload
 	 **/
	Shell function reload( Boolean clear=true ){
		if( arguments.clear ){
			variables.reader.clearScreen();
		}
		variables.reloadshell = true;
    	variables.keepRunning = false;

    	return this;
	}

	/**
	 * Returns the current console text
 	 **/
	string function getText() {
    	return variables.reader.getCursorBuffer().toString();
	}

	/**
	 * Sets the shell prompt
	 * @text.hint prompt text to set, if empty we use the default prompt
 	 **/
	Shell function setPrompt( text="" ) {
		if( !len( arguments.text ) ){
			arguments.text = variables.shellPrompt;
		} else {
			variables.shellPrompt = arguments.text;
		}
		variables.reader.setPrompt( variables.shellPrompt );
		return this;
	}

	/**
	 * ask the user a question and wait for response
	 * @message.hint message to prompt the user with
	 * 
	 * @return the response from the user
 	 **/
	string function ask( message ) {
		// read reponse
		var input = variables.reader.readLine( arguments.message );
		// Reset back to default prompt
		setPrompt();

		return input;
	}


	/**
	 * Wait until the user's next keystroke, returns the key pressed
	 * @message.message An optional message to display to the user such as "Press any key to continue."
	 * 
	 * @return code of key pressed
 	 **/
	string function waitForKey( message='' ) {
		var key = '';
		if( len( arguments.message ) ) {
			printString( arguments.message );
		}
		key = variables.reader.readCharacter();
		// Reset back to default prompt
		setPrompt();

		return key;
	}

	/**
	 * clears the console
	 *
	 * @note Almost works on Windows, but doesn't clear text background
	 * 
 	 **/
	Shell function clearScreen( addLines = true ) {
		// This outputs a double prompt due to the redrawLine() call
		//	reader.clearScreen();
	
		// A temporary workaround for windows. Since background colors aren't cleared
		// this will force them off the screen with blank lines before clearing.
		if( variables.fileSystem.isWindows() && arguments.addLines ) {
			var i = 0;
			while( ++i <= getTermHeight() + 5 ) {
				variables.reader.println();	
			}
		}
		
		variables.reader.print( '[2J' );
		variables.reader.print( '[1;1H' );

		return this;
	}

	/**
	 * Get's terminal width
  	 **/
	function getTermWidth() {
       	return variables.reader.getTerminal().getWidth();
	}

	/**
	 * Get's terminal height
  	 **/
	function getTermHeight() {
       	return variables.reader.getTerminal().getHeight();
	}

	/**
	 * Alias to get's current directory or use getPWD()
  	 **/
	function pwd() {
    	return variables.pwd;
	}

	/**
	* Get the temp dir in a safe manner
	*/
	string function getTempDir(){
		lock name="commandbox.tempdir" timeout="10" type="readOnly" throwOnTimeout="true"{
			return variables.tempDir;
		}
	}

	/**
	 * sets and renews temp directory
	 * @directory.hint directory to use
  	 **/
	Shell function setTempDir( required directory ){
        lock name="commandbox.tempdir" timeout="10" type="exclusive" throwOnTimeout="true"{

        	// Delete temp dir
	        var clearTemp = directoryExists( arguments.directory ) ? directoryDelete( arguments.directory, true ) : "";
	        
	        // Re-create it. Try 3 times.
	        var tries = 0;
        	try {
        		tries++;
		        directoryCreate( arguments.directory );
        	} catch (any e) {
        		if( tries <= 3 ) {
					variables.logger.info( 'Error creating temp directory [#arguments.directory#]. Trying again in 500ms.', 'Number of tries: #tries#' );
        			// Wait 500 ms and try again.  OS could be locking the dir
        			sleep( 500 );
        			retry;
        		} else {
					variables.logger.info( 'Error creating temp directory [#arguments.directory#]. Giving up now.', 'Tried #tries# times.' );
        			printError( e );        			
        		}
        	}

        	// set now that it is created.
        	variables.tempdir = arguments.directory;
        }

    	return this;
	}

	/**
	 * changes the current directory of the shell and returns the directory set.
	 * @directory.hint directory to CD to
  	 **/
	String function cd( directory="" ){
		// cleanup
		arguments.directory = replace( arguments.directory, "\", "/", "all" );
		// determine and change.
		if( !len( arguments.directory ) ){
			variables.pwd = variables.userDir;
		} else if( arguments.directory == "." || arguments.directory == "./" ){
			// do nothing
		} else if(directoryExists(directory)) {
	    	variables.pwd = arguments.directory;
		} else {
			return "cd: #arguments.directory#: No such file or directory";
		}
		return variables.pwd;
	}

	/**
	 * Prints a string to the reader console with auto flush
	 * @string.hint string to print (handles complex objects)
  	 **/
	Shell function printString( required string ){
		if( !isSimpleValue( arguments.string ) ){
			systemOutput( "[COMPLEX VALUE]\n" );
			writedump(var=arguments.string, output="console");
			arguments.string = "";
		}
    	variables.reader.print( arguments.string );
    	variables.reader.flush();

    	return this;
	}

	/**
	 * Runs the shell thread until exit flag is set
	 * @input.hint command line to run if running externally
  	 **/
    Boolean function run( input="" ) {
        var mask 	= "*";
        var trigger = "su";
        
		// init reload to false, just in case
        variables.reloadshell = false;

		try{
	        // Get input stream
	        if( arguments.input != "" ){
	        	 arguments.input &= chr(10);
	        	var inStream = createObject( "java", "java.io.ByteArrayInputStream" ).init( arguments.input.getBytes() );
	        	variables.reader.setInput( inStream );
	        }

	        // setup bell enabled + keep running flags
	        variables.reader.setBellEnabled( true );
	        variables.keepRunning = true;

	        var line ="";
			// Set default prompt on reader
			setPrompt();

			// while keep running
	        while( variables.keepRunning ){
	        	// check if running externally
				if( arguments.input != "" ){
					variables.keepRunning = false;
				}

				try {
					// Shell stops on this line while waiting for user input
		        	line = variables.reader.readLine();
				} catch( any er ) {
					printError( er );
					continue;
				}

	            // If we input the special word then we will mask the next line.
	            if( ( !isNull( trigger ) ) && ( line.compareTo( trigger ) == 0 ) ){
	                line = variables.reader.readLine( "password> ", javacast( "char", mask ) );
	            }

	            // If there's input, try to run it.
				if( len( trim( line ) ) ) {
					try{
						callCommand( line );
					} catch (any e) {
						printError( e );
					}
				}
				
				// Flush history buffer to disk. I could do this in the quit command
				// but then I would lose everything if the user just closes the window
				variables.reader.getHistory().flush();
				
	        } // end while keep running

		} catch( any e ){
			SystemOUtput( e.message & e.detail );
			printError( e );
		}

		return variables.reloadshell;
    }

	/**
	 * Call a command
 	 * @command.hint command name
 	 **/
	Shell function callCommand( String command="" )  {
		var result = variables.commandService.runCommandLine( arguments.command );
		if( !isNull( result ) && !isSimpleValue( result ) ){
			if( isArray( result ) ){
				return variables.reader.printColumns( result );
			}
			result = variables.formatterUtil.formatJson( serializeJSON( result ) );
			printString( result );
		} else if( !isNull( result ) && len( result ) ) {
			printString( result );
			// If the command output text that didn't end with a line break one, add one
			if( mid( result, len( result ), 1 ) != variables.CR ) {
				variables.reader.println();
			}
		}

		return this;
	}

	/**
	 * print an error to the console
	 * @err.hint Error object to print (only message is required)
  	 **/
	Shell function printError( required err ){
		variables.logger.error( '#arguments.err.message# #arguments.err.detail ?: ''#', arguments.err.stackTrace ?: '' );

		variables.reader.print( variables.print.boldRedText( "ERROR: " & variables.formatterUtil.HTML2ANSI( arguments.err.message ) ) );
		variables.reader.println();

		if( structKeyExists( arguments.err, 'detail' ) ) {
			variables.reader.print( variables.print.boldRedText( variables.formatterUtil.HTML2ANSI( arguments.err.detail ) ) );
			variables.reader.println();
		}
		if( structKeyExists( arguments.err, 'tagcontext' ) ){
			var lines = arrayLen( arguments.err.tagcontext );
			if( lines != 0 ){
				for( var idx=1; idx <= lines; idx++) {
					var tc = arguments.err.tagcontext[ idx ];
					if( len( tc.codeprinthtml ) ){
						if( idx > 1 ) {
							variables.reader.print( print.boldCyanText( "called from " ) );
						}
						variables.reader.print( variables.print.boldCyanText( "#tc.template#: line #tc.line##variables.CR#" ));
						variables.reader.print( variables.print.text( variables.formatterUtil.HTML2ANSI( tc.codeprinthtml ) ) );
					}
				}
			}
		}
		if( structKeyExists( arguments.err, 'stacktrace' ) ) {
			variables.reader.print( arguments.err.stacktrace );
		}

		variables.reader.println();

		return this;
	}

}
