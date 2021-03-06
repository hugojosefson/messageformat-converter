
MessageFormat = require 'messageformat'
mf = new MessageFormat 'en'
mfutil = require '../util'

module.exports = MessageFormatFormatter =

    # MessageFormat comes to us with keys and strings separate from each other, so this function
    # takes a [key, str] tuple.
    stringIn: ([key, str]) ->
        mfconv = require '../messageformat-converter'
        output = new mfconv.ConversionString key

        # We're going to use this function to recurse plurals, so optionally parse the input string
        # into a messageFormat tree.
        rootNode = str

        if typeof rootNode is 'string'
            try
                parsed = mf.parse rootNode
                rootNode = parsed.program
            catch e
                throw new Error 'Hmm, this appears to not be a messageFormat string:', str, e

        # First thing -- messageformat parses into a nested pattern tree for optimization purposes.
        # We only care about the leafs of that, so let's go ahead and traverse that tree.

        leaves = []
        fringe = rootNode.statements
        while fringe.length > 0
            thisNode = fringe.shift()
            if thisNode.statements
                fringe = thisNode.statements.concat fringe
            else
                leaves.push thisNode

        this.strParts = []
        # Cool. Now traverse and handle accordingly.
        for leaf in leaves

            # Case 1: basic string.
            if leaf.type is 'string'
                output.bits.push new mfconv.StringBit leaf.val
            else if leaf.type is 'messageFormatElement'

                # Case 2: variable string.
                unless leaf.elementFormat?
                    output.bits.push new mfconv.VariableBit leaf.argumentIndex

                # Case 3: plural stuff. (Or something else that will make us explode.)
                else
                    unless leaf.elementFormat.key is 'plural'
                        throw new Error 'Unsupported format type: ' + leaf.elementFormat.key 
                    pluralBit = new mfconv.PluralBit leaf.argumentIndex
                    output.bits.push pluralBit
                    for pluralForm in leaf.elementFormat.val.pluralForms
                        pluralBit.addMapping MessageFormatFormatter.stringIn [pluralForm.key, pluralForm.val]
        
        return output
                    
    # Returns a [key, str] tuple.
    stringOut: (conversionString) ->
        ret = ''
        for bit in conversionString.bits
            
            # StringBit
            if bit.type is 'string'
                ret += bit.str

            # VariableBit
            if bit.type is 'variable'
                ret += '{' + bit.varName + '}'

            # PluralBit
            if bit.type is 'plural'
                innerStrings = []
                for pluralString in bit.pluralStrings
                    [innerKey, innerStr] = MessageFormatFormatter.stringOut pluralString
                    innerStrings.push innerKey + '{' + innerStr + '}'
                ret += "{#{bit.pluralKey}, plural, #{innerStrings.join ' '}}"

        return [conversionString.key, ret]

    fileIn: (fileStr) ->
        mfconv = require '../messageformat-converter'
        obj = JSON.parse fileStr if typeof fileStr is 'string'
        obj = mfutil.flatten obj
        conversionStrings = (MessageFormatFormatter.stringIn [key, value] for key, value of obj)
        return new mfconv.ConversionFile conversionStrings

    fileOut: (conversionFile) ->
        mfconv = require '../messageformat-converter'
        ret = {}
        for conversionString in conversionFile.conversionStrings
            [key, value] = MessageFormatFormatter.stringOut conversionString
            ret[key] = value
        return JSON.stringify mfutil.unflatten ret
