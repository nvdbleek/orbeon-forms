<?xml version="1.0" encoding="utf-8"?>
<!--
    Copyright (C) 2008 Orbeon, Inc.

    This program is free software; you can redistribute it and/or modify it under the terms of the
    GNU Lesser General Public License as published by the Free Software Foundation; either version
    2.1 of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
    without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
    See the GNU Lesser General Public License for more details.

    The full text of the license is available at http://www.gnu.org/copyleft/lesser.html
-->
<p:config xmlns:p="http://www.orbeon.com/oxf/pipeline"
        xmlns:xs="http://www.w3.org/2001/XMLSchema"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
        xmlns:oxf="http://www.orbeon.com/oxf/processors"
        xmlns:xi="http://www.w3.org/2001/XInclude"
        xmlns:xforms="http://www.w3.org/2002/xforms"
        xmlns:ev="http://www.w3.org/2001/xml-events">

    <!-- Unrolled XHTML+XForms -->
    <p:param type="input" name="xforms"/>
    <!-- Request parameters -->
    <p:param type="input" name="parameters"/>
    <!-- PDF document -->
    <p:param type="output" name="data"/>

    <!-- Call XForms epilogue -->
    <p:processor name="oxf:pipeline">
        <p:input name="config" href="/ops/pfc/xforms-epilogue.xpl"/>
        <p:input name="data" href="#xforms"/>
        <p:input name="model-data"><null xsi:nil="true"/></p:input>
        <p:input name="instance" href="#parameters"/>
        <p:output name="xformed-data" id="xformed-data"/>
    </p:processor>

    <p:processor name="oxf:request">
        <p:input name="config">
            <config><include>/request/container-namespace</include></config>
        </p:input>
        <p:output name="data" id="request"/>
    </p:processor>

    <!-- Prepare XHTML before conversion to PDF -->
    <p:processor name="oxf:xslt">
        <p:input name="config">
            <xsl:transform version="2.0">
                <xsl:import href="oxf:/oxf/xslt/utils/copy.xsl"/>
                <!-- Remove portlet namespace from ids if present. Do this because in a portlet environment, the CSS
                     retrieved by oxf:xhtml-to-pdf doesn't know about the namespace. Not doing so, the CSS won't apply
                     and also this can cause a ClassCastException in Flying Saucer. -->
                <xsl:template match="@id">
                    <xsl:attribute name="id" select="substring-after(., doc('input:request')/*/container-namespace)"/>
                </xsl:template>
                <!-- While we are at it filter out scripts as they won't be used -->
                <xsl:template match="*:script"/>
                <!-- Remove all prefixes because Flying Saucer doesn't like them -->
                <xsl:template match="*">
                    <xsl:element name="{local-name()}">
                        <xsl:apply-templates select="@* | node()"/>
                    </xsl:element>
                </xsl:template>
            </xsl:transform>
        </p:input>
        <p:input name="data" href="#xformed-data"/>
        <p:input name="request" href="#request"/>
        <p:output name="data" id="xhtml-data"/>
    </p:processor>

    <!-- Serialize HTML to PDF -->
    <p:processor name="oxf:xhtml-to-pdf">
        <p:input name="data" href="#xhtml-data"/>
        <p:output name="data" ref="data"/>
    </p:processor>

    <!-- TODO: example of oxf:add-attribute processor adding content-disposition information -->
    <!-- TODO: build file name dynamically using requested document id? -->
    <!--<p:processor name="oxf:add-attribute">-->
        <!--<p:input name="data" href="#pdf-data"/>-->
        <!--<p:input name="config">-->
            <!--<config>-->
                <!--<match>/*</match>-->
                <!--<attribute-name>content-disposition</attribute-name>-->
                <!--<attribute-value>attachment; filename=form.pdf</attribute-value>-->
            <!--</config>-->
        <!--</p:input>-->
        <!--<p:output name="data" ref="data"/>-->
    <!--</p:processor>-->

</p:config>
