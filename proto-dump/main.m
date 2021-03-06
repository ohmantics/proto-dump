//
//  main.m
//  proto-dump
//
//  Copyright (c) 2013 Sean Patrick O'Brien. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CLUArgumentParser.h"
#import "CLULogging.h"
#import "PDDependencyProcessor.h"
#import "PDProtoFile.h"
#import "PDProtoFileExtractor.h"


static int extractProtobufDescriptors(NSString *inputPath, NSString *outputPath)
{
	// Load the input file.
	NSError *error = nil;
	NSData *data = [NSData dataWithContentsOfFile:inputPath options:0 error:&error];
	if (data == nil) {
		CLULog(@"proto-dump: %@", error.localizedDescription);
		return 1;
	}
	
	// Extract the Protobuf descriptors.
	NSArray *protoFiles = [PDProtoFileExtractor extractProtoFilesFromData:data error:&error];
	if (protoFiles == nil) {
		NSString *errorDescription = error.localizedDescription ?: @"An unknown error occured while extracting.";
		
		if ([error.domain isEqualToString:PDProtoFileExtractorErrorDomain] && error.code == PDProtoFileExtractorErrorDataContainsNoProtobufDescriptors) {
			// Use an error string which includes the filename.
			NSArray *pathComponents = [[NSFileManager defaultManager] componentsToDisplayForPath:inputPath];
			NSString *inputFileName = pathComponents.lastObject ?: inputPath.lastPathComponent;
					errorDescription = [NSString stringWithFormat:@"The file \u201C%@\u201D does not contain any Protobuf descriptors.", inputFileName];
		}
		
		CLULog(@"proto-dump: %@", errorDescription);
		
		return 1;
	}
	
	// Dump the extracted sources.
	if (outputPath != nil) {
		// Output paths take the form: <output>/<inputFilename>/<descriptorName>.proto
		NSString *adjustedOutputPath = [outputPath stringByAppendingPathComponent:inputPath.lastPathComponent];
		[[NSFileManager defaultManager] createDirectoryAtPath:adjustedOutputPath withIntermediateDirectories:YES attributes:nil error:NULL];
		
		for (PDProtoFile *protoFile in protoFiles) {
			NSString *source = protoFile.source;
			if (source != nil) {
				[source writeToFile:[adjustedOutputPath stringByAppendingPathComponent:protoFile.path] atomically:YES
						   encoding:NSUTF8StringEncoding error:NULL];
			}
		}
	} else {
		for (PDProtoFile *protoFile in protoFiles) {
			CLULog(@"%@", protoFile.source);
		}
	}
	
	return 0;
}

static void printVersionInfo(void)
{
	// FIXME: more legit versioning
	CLULog(@"proto-dump 0.1");
}

int main(int argc, const char *argv[])
{
	@autoreleasepool {
		// Construct an argument parser.
		CLUArgumentParser *argumentParser = [[CLUArgumentParser alloc] init];
		argumentParser.programName = [[NSString stringWithUTF8String:argv[0]] lastPathComponent];
		
		// Add option definitions for help, version, output and input.
		CLUOptionDefinition *helpOptionDefinition = [argumentParser addLiteralOptionWithShortNames:@"h" longNames:@"help"];
		CLUOptionDefinition *versionOptionDefinition = [argumentParser addLiteralOptionWithShortNames:@"v" longNames:@"version"];
		CLUStringOptionDefinition *outputOptionDefinition = [argumentParser addStringOptionWithShortNames:@"o" longNames:@"output"];
		CLUStringOptionDefinition *inputOptionDefinition = [argumentParser addStringOptionWithShortNames:nil longNames:nil];
		
		// Add descriptions and other requirements.
		helpOptionDefinition.optionDescription = @"Show usage information and exit";
		
		versionOptionDefinition.optionDescription = @"Show version information";
		
		outputOptionDefinition.dataTypeDescription = @"<output>";
		outputOptionDefinition.optionDescription = @"Write the .proto files to <output>";
		
		inputOptionDefinition.minCount = 1;
		inputOptionDefinition.dataTypeDescription = @"<input>";
		inputOptionDefinition.optionDescription = @"Extract Protobuf descriptors from <input>";
		
		// Parse the command line arguments.
		NSArray *errors = nil;
		BOOL parsingSucceeded = [argumentParser parseArguments:argv count:argc errors:&errors];
		
		BOOL shouldPrintHelp = helpOptionDefinition.count > 0;
		BOOL shouldPrintVersion = versionOptionDefinition.count > 0;
		BOOL shouldExitEarly = NO;
		int earlyExitStatus = 0;
		
		if ((shouldPrintHelp || shouldPrintVersion) && !parsingSucceeded) {
			// If we were asked to print help/version info, filter out errors regarding missing options.
			errors = [errors filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSError *error, NSDictionary *bindings) {
				if ([error.domain isEqualToString:CLUArgumentParserErrorDomain] && error.code == CLUArgumentParserMinCountError) {
					return NO;
				}
				
				return YES;
			}]];
			
			// If there are no errors left, parsing was successful.
			parsingSucceeded = errors.count == 0;
		}
		
		if (shouldPrintVersion) {
			printVersionInfo();
			
			// Exit early if there's no input path.
			shouldExitEarly = inputOptionDefinition.values.count == 0;
		}
		
		if (shouldPrintHelp || !parsingSucceeded) {
			// Print version info if we haven't already done so.
			if (!shouldPrintVersion) {
				printVersionInfo();
			}
			
			CLULog(@"Usage: %@", argumentParser.usageString);
			shouldExitEarly = YES;
		}
		
		// Print any errors that might have occured during parsing.
		if (!parsingSucceeded) {
			for (NSError *error in errors) {
				CLULog(@"%@", error.localizedFailureReason);
			}
			
			shouldExitEarly = YES;
			earlyExitStatus = 1;
		}
		
		if (shouldExitEarly) {
			return earlyExitStatus;
		}
		
		return extractProtobufDescriptors(inputOptionDefinition.values.lastObject, outputOptionDefinition.values.lastObject);
	}
}
