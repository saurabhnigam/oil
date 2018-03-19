# Copyright 2004-2005 Elemental Security, Inc. All Rights Reserved.
# Licensed to PSF under a Contributor Agreement.

# Modifications:
# Copyright 2006 Google, Inc. All Rights Reserved.
# Licensed to PSF under a Contributor Agreement.

"""Parser driver.

This provides a high-level interface to parse a file into a syntax tree.

"""

__author__ = "Guido van Rossum <guido@python.org>"

__all__ = ["Driver"]

# Python imports
import logging

# Pgen imports
from . import grammar, parse, token, tokenize


class Driver(object):

    def __init__(self, grammar, convert=None, logger=None):
        self.grammar = grammar
        if logger is None:
            logger = logging.getLogger()
        self.logger = logger
        self.convert = convert

    def parse_tokens(self, tokens, start_symbol=None, debug=False):
        """Parse a series of tokens and return the syntax tree."""
        # XXX Move the prefix computation into a wrapper around tokenize.
        p = parse.Parser(self.grammar, self.convert)
        p.setup(start=start_symbol)
        lineno = 1
        column = 0
        type_ = value = start = end = line_text = None
        prefix = ""
        for quintuple in tokens:
            type_, value, start, end, line_text = quintuple
            if start != (lineno, column):
                assert (lineno, column) <= start, ((lineno, column), start)
                s_lineno, s_column = start
                if lineno < s_lineno:
                    prefix += "\n" * (s_lineno - lineno)
                    lineno = s_lineno
                    column = 0
                if column < s_column:
                    prefix += line_text[column:s_column]
                    column = s_column
            if type_ in (tokenize.COMMENT, tokenize.NL):
                prefix += value
                lineno, column = end
                if value.endswith("\n"):
                    lineno += 1
                    column = 0
                continue
            if type_ == token.OP:
                type_ = grammar.opmap[value]
            if debug:
                self.logger.debug("%s %r (prefix=%r)",
                                  token.tok_name[type_], value, prefix)
            if p.addtoken(type_, value, (prefix, start)):
                if debug:
                    self.logger.debug("Stop.")
                break
            prefix = ""
            lineno, column = end
            if value.endswith("\n"):
                lineno += 1
                column = 0
        else:
            # We never broke out -- EOF is too soon (how can this happen???)
            raise parse.ParseError("incomplete input",
                                   type_, value, (prefix, start))
        return p.rootnode
