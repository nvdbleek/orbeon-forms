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
        xmlns:sql="http://orbeon.org/oxf/xml/sql"
        xmlns:odt="http://orbeon.org/oxf/xml/datatypes"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xmlns:xs="http://www.w3.org/2001/XMLSchema"
        xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
        xmlns:oxf="http://www.orbeon.com/oxf/processors"
        xmlns:xi="http://www.w3.org/2001/XInclude"
        xmlns:xforms="http://www.w3.org/2002/xforms"
        xmlns:ev="http://www.w3.org/2001/xml-events"
        xmlns:f="http//www.orbeon.com/function"
        xmlns:fr="http://orbeon.org/oxf/xml/form-runner">

    <p:param type="input" name="instance"/>

    <!-- NOTE: It's disappointing that we have to use oxf:request/oxf:perl5-matcher rather than using the page flow
         directly, but because we want to support the PUT and POST methods, this is currently the only solution. -->
    <p:processor name="oxf:request">
        <p:input name="config">
            <config stream-type="xs:anyURI">
                <include>/request/request-path</include>
                <include>/request/content-type</include>
                <include>/request/method</include>
                <include>/request/headers/header[name = 'orbeon-username' or name = 'orbeon-roles' or name = 'orbeon-datasource' or name = 'orbeon-create-flat-view']</include>
                <include>/request/body</include>
            </config>
        </p:input>
        <p:output name="data" id="request"/>
    </p:processor>
    <p:processor name="oxf:perl5-matcher">
        <p:input name="config"><config>/fr/service/oracle/crud/([^/]+)/([^/]+)/((form)/([^/]+)|(data)/(([^/]+)/([^/]+))?)</config></p:input>
        <p:input name="data" href="#request#xpointer(/request/request-path)"/>
        <p:output name="data" id="matcher-groups"/>
    </p:processor>

    <!-- Build a document with a description of the request -->
    <p:processor name="oxf:xslt">
        <p:input name="matcher-groups" href="#matcher-groups"/>
        <p:input name="instance" href="#instance"/>
        <p:input name="request" href="#request"/>
        <p:input name="data"><dummy/></p:input>
        <p:input name="config">
            <request xsl:version="2.0">
                <xsl:variable name="matcher-groups" as="element(group)+" select="doc('input:matcher-groups')/result/group"/>
                <xsl:variable name="request" as="element(request)" select="doc('input:request')/request"/>
                <content-type><xsl:value-of select="$request/content-type"/></content-type>
                <document><xsl:copy-of select="doc('input:instance')"/></document>
                <timestamp><xsl:value-of select="current-dateTime()"/></timestamp>
                <username><xsl:value-of select="$request/headers/header[name = 'orbeon-username']/value"/></username>
                <roles><xsl:value-of select="$request/headers/header[name = 'orbeon-roles']/value"/></roles>
                <app><xsl:value-of select="$matcher-groups[1]"/></app>
                <form><xsl:value-of select="$matcher-groups[2]"/></form>
                <xsl:variable name="type" as="xs:string" select="if ($matcher-groups[4] = 'form') then 'form' else 'data'"/>
                <type><xsl:value-of select="$type"/></type>
                <xsl:if test="$type = 'data' and $matcher-groups[8] != ''">                             <!-- Document id is only used for data; might be missing for operations over a collection -->
                    <document-id><xsl:value-of select="$matcher-groups[8]"/></document-id>
                </xsl:if>
                <xsl:if test="$type = 'form' or $matcher-groups[9] != ''">                              <!-- Filename isn't present for operations over an app/form collection -->
                    <filename><xsl:value-of select="if ($type = 'data') then $matcher-groups[9] else $matcher-groups[5]"/></filename>
                </xsl:if>
                <sql:datasource><xsl:value-of select="$request/headers/header[name = 'orbeon-datasource']/value/string() treat as xs:string"/></sql:datasource>
                <create-flat-view>
                    <xsl:variable name="create-flat-view-property" as="xs:string?" select="$request/headers/header[name = 'orbeon-create-flat-view']/value/string()"/>
                    <xsl:value-of select="($create-flat-view-property, 'false')[1]"/>
                </create-flat-view>
                <xsl:copy-of select="$request/body"/>
            </request>
        </p:input>
        <p:output name="data" id="request-description"/>
    </p:processor>

    <p:processor name="oxf:null-serializer">
        <p:input name="data" href="#request-description"/>
    </p:processor>

    <!-- Discriminate based on the HTTP method and content type -->
    <p:choose href="#request">
        <!-- Handle binary and XML GET -->
        <p:when test="/*/method = 'GET'">

            <p:processor name="oxf:unsafe-xslt">
                <p:input name="data" href="#request-description"/>
                <p:input name="config">
                    <sql:config xsl:version="2.0">
                        <sql-out>
                            <sql:connection>
                                <xsl:copy-of select="/request/sql:datasource"/>

                                <xsl:variable name="is-data" as="xs:boolean" select="/request/type = 'data'"/>
                                <xsl:variable name="is-attachment" as="xs:boolean" select="not(ends-with(/request/filename, '.xml') or ends-with(/request/filename, '.xhtml'))"/>
                                <xsl:variable name="table-name" as="xs:string" select="concat(
                                    if ($is-data) then 'orbeon_form_data' else 'orbeon_form_definition',
                                    if ($is-attachment) then '_attach' else '')"/>

                                <sql:execute>
                                    <sql:query>
                                        select
                                            last_modified,
                                            <xsl:if test="not($is-attachment)">t.xml.getClobVal() xml</xsl:if>
                                            <xsl:if test="$is-attachment">file_content</xsl:if>
                                        from <xsl:value-of select="$table-name"/> t
                                            where app = <sql:param type="xs:string" select="/request/app"/>
                                            and form = <sql:param type="xs:string" select="/request/form"/>
                                            <xsl:if test="$is-data">and document_id = <sql:param type="xs:string" select="/request/document-id"/></xsl:if>
                                            <xsl:if test="$is-attachment">and file_name = <sql:param type="xs:string" select="/request/filename"/></xsl:if>
                                            and last_modified = (
                                                select max(last_modified) from <xsl:value-of select="$table-name"/>
                                                where app = <sql:param type="xs:string" select="/request/app"/>
                                                and form = <sql:param type="xs:string" select="/request/form"/>
                                                <xsl:if test="$is-data">and document_id = <sql:param type="xs:string" select="/request/document-id"/></xsl:if>
                                                <xsl:if test="$is-attachment">and file_name = <sql:param type="xs:string" select="/request/filename"/></xsl:if>
                                            )
                                            <!-- This will prevent request for document that have been deleted to return a delete doc -->
                                            and deleted = 'N'
                                    </sql:query>
                                    <sql:result-set>
                                        <sql:row-iterator>
                                            <last-modified>
                                                <sql:get-column-value column="last_modified" type="xs:dateTime"/>
                                            </last-modified>
                                            <data>
                                                <xsl:choose>
                                                    <xsl:when test="$is-attachment">
                                                        <sql:get-column-value column="file_content" type="xs:base64Binary"/>
                                                    </xsl:when>
                                                    <xsl:otherwise>
                                                        <sql:get-column-value column="xml" type="odt:xmlFragment"/>
                                                    </xsl:otherwise>
                                                </xsl:choose>
                                            </data>
                                        </sql:row-iterator>
                                    </sql:result-set>
                                </sql:execute>
                            </sql:connection>
                        </sql-out>
                    </sql:config>
                </p:input>
                <p:output name="data" id="sql-config"/>
            </p:processor>

            <p:processor name="oxf:sql">
                <p:input name="data" href="#request-description"/>
                <p:input name="config" href="#sql-config"/>
                <p:output name="data" id="sql-out"/>
            </p:processor>

            <p:choose href="aggregate('root', #request-description, #sql-out)">
                <!-- Test whether we got data as well as the extension type before trying to parse as XML -->
                <p:when test="/*/sql-out/data and (ends-with(/*/request/filename, '.xml') or ends-with(/*/request/filename, '.xhtml'))">
                    <!-- Convert and serialize to XML -->
                    <p:processor name="oxf:xml-converter">
                        <p:input name="config">
                            <config>
                                <indent>false</indent>
                                <encoding>utf-8</encoding>
                            </config>
                        </p:input>
                        <p:input name="data" transform="oxf:unsafe-xslt" href="#sql-out">
                            <!-- We don't use XPointer here because XPointer doesn't deal correctly with namespaces -->
                            <xsl:stylesheet version="2.0">
                                <xsl:template match="/">
                                    <xsl:copy-of select="/sql-out/data/*"/>
                                </xsl:template>
                            </xsl:stylesheet>
                        </p:input>
                        <p:output name="data" id="sql-out-converted"/>
                    </p:processor>
                </p:when>
                <p:otherwise>
                    <!-- Add the xsi:type in a separate step, as the SQL Processor doesn't pass namespace declaration for xs even if the namespace is declared on the element -->
                    <p:processor name="oxf:xslt">
                        <p:input name="data" href="#sql-out"/>
                        <p:input name="config">
                            <document xsi:type="xs:base64Binary" xsl:version="2.0">
                                <xsl:value-of select="/sql-out/data"/>
                            </document>
                        </p:input>
                        <p:output name="data" id="sql-out-converted"/>
                    </p:processor>
                </p:otherwise>
            </p:choose>

            <!-- TODO: Remove code duplication with above -->
            <p:processor name="oxf:unsafe-xslt">
                <p:input name="data" href="#request-description"/>
                <p:input name="config">
                    <sql:config xsl:version="2.0">
                        <last-modified>
                            <sql:connection>
                                <xsl:copy-of select="/request/sql:datasource"/>

                                <xsl:variable name="is-data" as="xs:boolean" select="/request/type = 'data'"/>
                                <xsl:variable name="is-attachment" as="xs:boolean" select="not(ends-with(/request/filename, '.xml') or ends-with(/request/filename, '.xhtml'))"/>
                                <xsl:variable name="table-name" as="xs:string" select="concat(
                                    if ($is-data) then 'orbeon_form_data' else 'orbeon_form_definition',
                                    if ($is-attachment) then '_attach' else '')"/>

                                <sql:execute>
                                    <sql:query>
                                        select
                                            last_modified
                                        from <xsl:value-of select="$table-name"/> t
                                            where app = <sql:param type="xs:string" select="/request/app"/>
                                            and form = <sql:param type="xs:string" select="/request/form"/>
                                            <xsl:if test="$is-data">and document_id = <sql:param type="xs:string" select="/request/document-id"/></xsl:if>
                                            <xsl:if test="$is-attachment">and file_name = <sql:param type="xs:string" select="/request/filename"/></xsl:if>
                                            and last_modified = (
                                                select max(last_modified) from <xsl:value-of select="$table-name"/>
                                                where app = <sql:param type="xs:string" select="/request/app"/>
                                                and form = <sql:param type="xs:string" select="/request/form"/>
                                                <xsl:if test="$is-data">and document_id = <sql:param type="xs:string" select="/request/document-id"/></xsl:if>
                                                <xsl:if test="$is-attachment">and file_name = <sql:param type="xs:string" select="/request/filename"/></xsl:if>
                                            )
                                            <!-- This will prevent request for document that have been deleted to return a delete doc -->
                                            and deleted = 'N'
                                    </sql:query>
                                    <sql:result-set>
                                        <sql:row-iterator>
                                            <sql:get-column-value column="last_modified" type="xs:dateTime"/>
                                        </sql:row-iterator>
                                    </sql:result-set>
                                </sql:execute>
                            </sql:connection>
                        </last-modified>
                    </sql:config>
                </p:input>
                <p:output name="data" id="sql-validity-config"/>
            </p:processor>

            <p:processor name="oxf:sql">
                <p:input name="data" href="#request-description"/>
                <p:input name="config" href="#sql-validity-config"/>
                <p:output name="data" id="sql-validity-out"/>
            </p:processor>

            <!--
                Cache processor:

                - validity is retrieved from the database
                - key is the request
             -->
            <p:processor name="oxf:cache">
                <p:input name="data" href="#sql-out-converted"/>
                <p:input name="key" href="#request"/>
                <p:input name="validity" href="#sql-validity-out"/>
                <p:output name="data" id="converted"/>
            </p:processor>

            <!-- Serialize out as is -->
            <p:processor name="oxf:http-serializer">
                <p:input name="config">
                    <config>
                        <cache-control>
                            <use-local-cache>false</use-local-cache>
                        </cache-control>
                        <!-- NOTE: No need to output Last-Modified header as oxf:cache is providing validity that is used by the serializer -->
                    </config>
                </p:input>
                <p:input name="data" href="#converted"/>
            </p:processor>

        </p:when>
        <p:otherwise>
            <!-- Discriminate based on the HTTP method and content type -->
            <p:choose href="#request">

                <!-- DELETE -->
                <p:when test="/*/method = 'DELETE'">

                    <p:processor name="oxf:sql">
                        <p:input name="data" href="#request-description"/>
                        <p:input name="config" transform="oxf:unsafe-xslt" href="#request-description">
                            <sql:config xsl:version="2.0">
                                <result>
                                    <sql:connection>
                                        <xsl:copy-of select="/request/sql:datasource"/>
                                        <sql:execute>
                                            <sql:update>
                                                <xsl:variable name="is-data" as="xs:boolean" select="/request/type = 'data'"/>
                                                <xsl:variable name="has-document-id" as="xs:boolean" select="exists(/request/document-id)"/>
                                                <xsl:variable name="table-name" as="xs:string" select="if ($is-data) then 'orbeon_form_data' else 'orbeon_form_definition'"/>

                                                insert into <xsl:value-of select="$table-name"/>
                                                    <!-- TODO: This list of columns only works for the data (not form definition) table -->
                                                    (created, last_modified, username, app, form, <xsl:if test="$is-data">document_id,</xsl:if> deleted, xml)
                                                select
                                                    created,
                                                    <sql:param type="xs:dateTime" select="/request/timestamp"/>,
                                                    <sql:param type="xs:string" select="/request/username"/>,
                                                    app, form, <xsl:if test="$is-data">document_id,</xsl:if>
                                                    'Y', xml
                                                from
                                                    (
                                                        select t.*, dense_rank() over (partition by <xsl:value-of select="if ($is-data) then 'document_id' else 'app, form'"/> order by last_modified desc) as latest
                                                        from <xsl:value-of select="$table-name"/> t
                                                        where
                                                            app = <sql:param type="xs:string" select="/request/app"/>
                                                            and form = <sql:param type="xs:string" select="/request/form"/>
                                                            <xsl:if test="$is-data and $has-document-id">and document_id = <sql:param type="xs:string" select="/request/document-id"/></xsl:if>
                                                    )
                                                where latest = 1 and deleted = 'N'
                                            </sql:update>
                                        </sql:execute>
                                    </sql:connection>
                                </result>
                            </sql:config>
                        </p:input>
                    </p:processor>

                </p:when>

                <!-- PUT -->
                <p:when test="/*/method = 'PUT'">

                    <!-- Store data -->
                    <p:processor name="oxf:sql">
                        <p:input name="data" href="#request-description"/>
                        <p:input name="config" transform="oxf:unsafe-xslt" href="#request-description">
                            <sql:config xsl:version="2.0">
                                <result>
                                    <sql:connection>
                                        <xsl:copy-of select="/request/sql:datasource"/>
                                        <sql:execute>
                                            <sql:update>
                                                <xsl:variable name="is-data" as="xs:boolean" select="/request/type = 'data'"/>
                                                <xsl:variable name="is-attachment" as="xs:boolean" select="not(/request/content-type = ('application/xml', 'text/xml') or ends-with(/request/content-type, '+xml'))"/>
                                                <xsl:variable name="table-name" as="xs:string" select="concat(
                                                    if ($is-data) then 'orbeon_form_data' else 'orbeon_form_definition',
                                                    if ($is-attachment) then '_attach' else '')"/>
                                                declare
                                                    last_last_modified timestamp;
                                                    last_created timestamp;
                                                    last_deleted char(1);
                                                begin
                                                    <!-- Get last modified and creation date for this document, if there is one -->
                                                    select max(last_modified), max(created) into last_last_modified, last_created
                                                    from (
                                                        (
                                                            select max(last_modified) last_modified, max(created) created
                                                            from <xsl:value-of select="$table-name"/>
                                                            where
                                                                app = <sql:param type="xs:string" select="/request/app"/>
                                                                and form = <sql:param type="xs:string" select="/request/form"/>
                                                                <xsl:if test="$is-data">
                                                                    and document_id = <sql:param type="xs:string" select="/request/document-id"/>
                                                                </xsl:if>
                                                                <xsl:if test="$is-attachment">
                                                                    and file_name = <sql:param type="xs:string" select="/request/filename"/>
                                                                </xsl:if>
                                                        ) union all ( select null last_modified, null created from dual )
                                                    ) ;
                                                    <!-- If there is a document, see if that document was deleted -->
                                                    if last_last_modified is not null then
                                                        select deleted into last_deleted
                                                        from <xsl:value-of select="$table-name"/>
                                                        where
                                                            app = <sql:param type="xs:string" select="/request/app"/>
                                                            and form = <sql:param type="xs:string" select="/request/form"/>
                                                            <xsl:if test="$is-data">
                                                                and document_id = <sql:param type="xs:string" select="/request/document-id"/>
                                                            </xsl:if>
                                                            <xsl:if test="$is-attachment">
                                                                and file_name = <sql:param type="xs:string" select="/request/filename"/>
                                                            </xsl:if>
                                                            and last_modified = last_last_modified ;
                                                    end if;
                                                    <!-- If this document hasn't been created, use current time stamp -->
                                                    if last_deleted is null or last_deleted = 'Y' then
                                                        last_created := <sql:param type="xs:dateTime" select="/request/timestamp"/>;
                                                    end if;
                                                    <!-- If we don't, insert one -->
                                                    insert
                                                        into <xsl:value-of select="$table-name"/>
                                                        (created, last_modified, username, app, form, <xsl:if test="$is-data">document_id,</xsl:if> deleted,
                                                            <xsl:if test="$is-attachment">file_name, file_content</xsl:if>
                                                            <xsl:if test="not($is-attachment)">xml</xsl:if>)
                                                        values (
                                                            last_created,
                                                            <sql:param type="xs:dateTime" select="/request/timestamp"/>,
                                                            <sql:param type="xs:string" select="/request/username"/>,
                                                            <sql:param type="xs:string" select="/request/app"/>,
                                                            <sql:param type="xs:string" select="/request/form"/>,
                                                            <xsl:if test="$is-data">
                                                                <sql:param type="xs:string" select="/request/document-id"/>,
                                                            </xsl:if>
                                                            'N',
                                                            <xsl:if test="$is-attachment">
                                                                <sql:param type="xs:string" select="/request/filename"/>,
                                                                <sql:param type="xs:anyURI" select="/request/body"/>
                                                            </xsl:if>
                                                            <xsl:if test="not($is-attachment)">
                                                                XMLType(<sql:param type="odt:xmlFragment" sql-type="clob" select="/request/document/*"/>)
                                                                <!-- See comments above -->
                                                                <!--XMLType(<sql:param type="odt:xmlFragment" sql-type="clob" select="saxon:parse(/request/document)"/>)-->
                                                            </xsl:if>
                                                        );
                                                end;
                                            </sql:update>
                                        </sql:execute>
                                    </sql:connection>
                                </result>
                            </sql:config>
                        </p:input>
                    </p:processor>

                    <!-- For form data, create view -->
                    <p:choose href="#request-description">
                        <p:when test="/request/type = 'form' and /request/filename = 'form.xhtml' and /request/create-flat-view = 'true'">
                            <p:processor name="oxf:unsafe-xslt">
                                <p:input name="data" href="#request-description"/>
                                <p:input name="config">
                                    <xsl:stylesheet version="2.0">
                                        <xsl:import href="sql-utils.xsl"/>
                                        <xsl:template match="/">

                                            <!-- Compute view name -->
                                            <!-- Max name length is 30. -9 for "orbeon_f_", leaves 21 characters -->
                                            <!-- Just convert to SQL format without truncating (hence the 99) -->
                                            <xsl:variable name="app-xml" select="f:xml-to-sql-id(/request/app, 99)"/>
                                            <xsl:variable name="form-xml" select="f:xml-to-sql-id(/request/form, 99)"/>
                                            <xsl:variable name="mv-name" select="concat('ORBEON_F_',
                                                    if (string-length($app-xml) + string-length($form-xml) le 20) then concat($app-xml, '_', $form-xml)
                                                    else if (string-length($app-xml) gt 10 and string-length($form-xml) gt 10) then concat(substring($app-xml, 1, 10), '_', substring($form-xml, 1, 10))
                                                    else if (string-length($app-xml) gt 10) then concat(substring($app-xml, 1, 20 - string-length($form-xml)), '_', $form-xml)
                                                    else concat($app-xml, '_', substring($form-xml, 1, 20 - string-length($app-xml)))
                                                )"/>

                                            <sql:config>
                                                <result>
                                                    <sql:connection>
                                                        <xsl:copy-of select="/request/sql:datasource"/>
                                                        <sql:execute>
                                                            <sql:update>
                                                                <xsl:variable name="metadata-column" as="xs:string+" select="('document_id', 'created', 'last_modified', 'username')"/>
                                                                <xsl:variable name="paths-ids" as="xs:string*" select="f:document-to-paths-ids(/request/document, $metadata-column)"/>
                                                                create or replace view <xsl:value-of select="$mv-name"/> as
                                                                select
                                                                    <!-- Metadata columns -->
                                                                    <xsl:value-of select="string-join(for $c in $metadata-column return concat($c, ' ', 'metadata_', $c), ', ')"/>
                                                                    <!-- Columns corresponding to elements in the XML data -->
                                                                    <xsl:for-each select="1 to count($paths-ids) div 2">
                                                                        <xsl:variable name="i" select="position()"/>
                                                                        , extractValue(xml, '/*/<xsl:value-of select="$paths-ids[$i * 2 - 1]"/>')
                                                                        "<xsl:value-of select="$paths-ids[$i * 2]"/>"
                                                                    </xsl:for-each>
                                                                from (
                                                                    select d.*, dense_rank() over (partition by document_id order by last_modified desc) as latest
                                                                    from orbeon_form_data d
                                                                    where
                                                                        <!-- NOTE: Generate app/form name in SQL, as Oracle doesn't allow bind variables for data definition operations -->
                                                                        app = '<xsl:value-of select="f:escape-sql(/request/app)"/>'
                                                                        and form = '<xsl:value-of select="f:escape-sql(/request/form)"/>'
                                                                    )
                                                                where latest = 1 and deleted = 'N'
                                                            </sql:update>
                                                        </sql:execute>
                                                    </sql:connection>
                                                </result>
                                            </sql:config>
                                        </xsl:template>
                                    </xsl:stylesheet>
                                </p:input>
                                <p:output name="data" id="create-sql"/>
                            </p:processor>
                            <p:processor name="oxf:sql">
                                <p:input name="data"><dummy/></p:input>
                                <p:input name="config" href="#create-sql" debug="create-sql"/>
                            </p:processor>
                        </p:when>
                    </p:choose>
                </p:when>
            </p:choose>

            <p:processor name="oxf:xml-converter">
                <p:input name="config">
                    <config>
                        <indent>false</indent>
                        <encoding>utf-8</encoding>
                    </config>
                </p:input>
                <p:input name="data"><dummy/></p:input>
                <p:output name="data" id="converted"/>
            </p:processor>
            <p:processor name="oxf:http-serializer">
                <p:input name="config">
                    <config>
                        <cache-control>
                            <use-local-cache>false</use-local-cache>
                        </cache-control>
                    </config>
                </p:input>
                <p:input name="data" href="#converted"/>
            </p:processor>
        </p:otherwise>

    </p:choose>

</p:config>