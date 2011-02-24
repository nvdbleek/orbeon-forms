<!--
  Copyright (C) 2011 Orbeon, Inc.
  
  This program is free software; you can redistribute it and/or modify it under the terms of the
  GNU Lesser General Public License as published by the Free Software Foundation; either version
  2.1 of the License, or (at your option) any later version.

  This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
  See the GNU Lesser General Public License for more details.

  The full text of the license is available at http://www.gnu.org/copyleft/lesser.html
  -->
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xsl:version="2.0">
    <head>
        <title><xsl:value-of select="/*/@title"/></title>
        <style type="text/css">
            .examples .example { float: left; width: 360px; height: 455px; margin: 0 .5em .5em 0; border-right: 1px solid #ccc; border-bottom: 1px solid #ccc }
            .examples .example .image { height: 310px; overflow-y: auto; overflow-x: hidden; padding: 1px 0 } <!-- padding 1px to make FF 3.6 happy -->
            .examples .example img { border: none; display: block; margin: 0 auto; padding: 1px 0 1px }
            .examples .example:hover { background-color: #FFCC66 }
            .examples .example h2 { color: #004B92; font-size: 14px; margin-top: 0; margin-bottom: .3em }
            .examples .example .description { padding: .5em 1em; font-family: georgia,serif; font-size: 14px; line-height: 1.3 }
            .examples .example.last .image { margin-top: 5em }
            .examples .example.last .description {  text-align: center; font-style: italic }
            .examples .example.last .image { height: auto }
        </style>
    </head>
    <body>
        <div class="examples">
            <xsl:for-each select="/*/example">
                <div class="example{if (position() = last()) then ' last' else ''}">
                    <xsl:if test="@title">
                        <h2><xsl:value-of select="@title"/></h2>
                    </xsl:if>
                    <div class="image">
                        <a href="{@href}"><img src="{@img}" alt="{@title}"/></a>
                    </div>
                    <p class="description">
                        <xsl:copy-of select="* | text()"/>
                    </p>
                </div>
            </xsl:for-each>
            <div class="cleaner"/>
        </div>
    </body>
</html>

