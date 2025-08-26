-- Formats the group description. If the description is null or contains placeholder
-- text, it will be set to null. Otherwise, it will clean up the description by converting
-- Markdown to plain text, removing any HTML tags, and trimming it to a maximum length of
-- 500.
create or replace function format_group_description(p_group json)
returns json as $$
declare
    v_description text;
    v_result text;
begin
    v_description := p_group->>'description';
    
    -- Return early for null or placeholder text
    if v_description is null then
        return jsonb_strip_nulls(jsonb_set(p_group::jsonb, '{description}', 'null'))::json;
    end if;
    
    if v_description like '%PLEASE ADD A DESCRIPTION HERE%'
      or v_description like '%DESCRIPTION GOES HERE%'
      or v_description like '%ADD DESCRIPTION HERE%'
      or v_description like '%PLEASE UPDATE THE BELOW DESCRIPTION%'
      or v_description like '%PLEASE UPDATE THE DESCRIPTION HERE%' then
        return jsonb_strip_nulls(jsonb_set(p_group::jsonb, '{description}', 'null'))::json;
    end if;
    
    -- Clean up the description
    v_result := v_description;
    
    -- Replace only &nbsp; first, keep other entities for proper ordering
    v_result := replace(v_result, '&nbsp;', ' ');
    
    -- Remove code blocks first (to avoid processing their content)
    v_result := regexp_replace(v_result, '```[^`]*```', '', 'g');
    v_result := regexp_replace(v_result, '``[^`]+``', '', 'g');
    v_result := regexp_replace(v_result, '`[^`]+`', '', 'g');
    
    -- Remove reference definitions
    v_result := regexp_replace(v_result, '^\s*\[[^\]]+\]:\s+.*$', '', 'gm');
    v_result := regexp_replace(v_result, '^\s*\[\^[^\]]+\]:\s+.*$', '', 'gm');
    
    -- Handle images (remove completely)
    v_result := regexp_replace(v_result, '!\[[^\]]*\]\([^)]*\)', '', 'g');
    v_result := regexp_replace(v_result, '!\[[^\]]*\]\[[^\]]*\]', '', 'g');
    
    -- Handle links (keep text, remove URL)
    v_result := regexp_replace(v_result, '\[([^\]]*)\]\([^)]*\)', '\1', 'g');
    v_result := regexp_replace(v_result, '\[([^\]]*)\]\[[^\]]*\]', '\1', 'g');
    
    -- Remove headers
    v_result := regexp_replace(v_result, '^#{1,6}\s+', '', 'gm');
    
    -- Remove list markers (including task lists)
    v_result := regexp_replace(v_result, '^\s*[-*+]\s+\[[xX ]\]\s+', '', 'gm');
    v_result := regexp_replace(v_result, '^\s*[-*+]\s+', '', 'gm');
    v_result := regexp_replace(v_result, '^\s*\d+\.\s+', '', 'gm');
    
    -- Remove blockquotes and alerts
    v_result := regexp_replace(v_result, '^\s*>\s+\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*', '', 'gmi');
    v_result := regexp_replace(v_result, '^\s*>\s+', '', 'gm');
    
    -- Remove emphasis markers (order matters to handle nested emphasis)
    v_result := regexp_replace(v_result, '\*\*\*([^*]+)\*\*\*', '\1', 'g');
    v_result := regexp_replace(v_result, '___([^_]+)___', '\1', 'g');
    v_result := regexp_replace(v_result, '\*\*([^*]+)\*\*', '\1', 'g');
    v_result := regexp_replace(v_result, '__([^_]+)__', '\1', 'g');
    v_result := regexp_replace(v_result, '\*([^*\s][^*]*[^*\s])\*', '\1', 'g');
    v_result := regexp_replace(v_result, '_([^_\s][^_]*[^_\s])_', '\1', 'g');
    
    -- Remove strikethrough
    v_result := regexp_replace(v_result, '~~([^~]+)~~', '\1', 'g');
    
    -- Remove table formatting
    v_result := regexp_replace(v_result, '\|[-:\s]+\|', '', 'g');  -- Remove separator patterns
    v_result := regexp_replace(v_result, '\s+[-:]{2,}\s+', ' ', 'g');  -- Remove remaining separators
    v_result := regexp_replace(v_result, '\|', ' ', 'g');  -- Then replace pipes with spaces
    
    -- Remove horizontal rules
    v_result := regexp_replace(v_result, '^\s*[-*_]{3,}\s*$', '', 'gm');
    
    -- Remove emoji codes
    v_result := regexp_replace(v_result, ':[a-zA-Z0-9_+-]+:', '', 'g');
    
    -- Remove footnote references
    v_result := regexp_replace(v_result, '\[\^[^\]]+\]', '', 'g');
    
    -- Keep @mentions and #references (GitHub flavored) - user requested to keep these
    
    -- Remove any remaining HTML tags (fallback)
    v_result := regexp_replace(v_result, '<[^>]+>', '', 'g');
    
    -- Remove encoded HTML tags and decode other entities
    v_result := regexp_replace(v_result, '&lt;[^&]*&gt;', '', 'g');  -- Remove encoded tags with content
    v_result := replace(v_result, '&lt;', '');  -- Remove any remaining &lt;
    v_result := replace(v_result, '&gt;', '');  -- Remove any remaining &gt;  
    v_result := replace(v_result, '&quot;', '"');
    v_result := replace(v_result, '&amp;', '&');  -- Must be last to avoid double-decoding
    
    -- Clean up whitespace
    v_result := regexp_replace(v_result, '\s+', ' ', 'g');
    v_result := trim(v_result);
    
    -- Truncate to 500 characters
    v_result := substring(v_result for 500);
    
    -- Update the JSON and return
    return jsonb_strip_nulls(jsonb_set(p_group::jsonb, '{description}', to_jsonb(v_result)))::json;
end;
$$ language plpgsql;
