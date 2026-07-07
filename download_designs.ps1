$urls = @{
    "1_splash.html" = "https://contribution.usercontent.google.com/download?c=CgthaWRhX2NvZGVmeBJ8Eh1hcHBfY29tcGFuaW9uX2dlbmVyYXRlZF9maWxlcxpbCiVodG1sXzAwMDY1NjAxYTFiMzE2MTIwMWE2MmMwOGJjMDBmYzI5EgsSBxCO-NuM-RoYAZIBJAoKcHJvamVjdF9pZBIWQhQxMTg3MjA0Mzk0NjY1OTk3OTg4NQ&filename=&opi=89354086"
    "2_search.html" = "https://contribution.usercontent.google.com/download?c=CgthaWRhX2NvZGVmeBJ8Eh1hcHBfY29tcGFuaW9uX2dlbmVyYXRlZF9maWxlcxpbCiVodG1sXzAwMDY1NjAyMTQ4Yjc4ZWEwMWE2MGU1M2JmMDQ2M2E1EgsSBxCO-NuM-RoYAZIBJAoKcHJvamVjdF9pZBIWQhQxMTg3MjA0Mzk0NjY1OTk3OTg4NQ&filename=&opi=89354086"
    "3_home.html" = "https://contribution.usercontent.google.com/download?c=CgthaWRhX2NvZGVmeBJ8Eh1hcHBfY29tcGFuaW9uX2dlbmVyYXRlZF9maWxlcxpbCiVodG1sXzAwMDY1NjAxZWJkNjA2ZDAwMzgzOGVkYmQ5MGZlMmI1EgsSBxCO-NuM-RoYAZIBJAoKcHJvamVjdF9pZBIWQhQxMTg3MjA0Mzk0NjY1OTk3OTg4NQ&filename=&opi=89354086"
    "4_library1.html" = "https://contribution.usercontent.google.com/download?c=CgthaWRhX2NvZGVmeBJ8Eh1hcHBfY29tcGFuaW9uX2dlbmVyYXRlZF9maWxlcxpbCiVodG1sXzAwMDY1NjAyMTJkYzkzZGIwMzRhNGUwNzI1MDhhZTgyEgsSBxCO-NuM-RoYAZIBJAoKcHJvamVjdF9pZBIWQhQxMTg3MjA0Mzk0NjY1OTk3OTg4NQ&filename=&opi=89354086"
    "5_queue.html" = "https://contribution.usercontent.google.com/download?c=CgthaWRhX2NvZGVmeBJ8Eh1hcHBfY29tcGFuaW9uX2dlbmVyYXRlZF9maWxlcxpbCiVodG1sXzA0YWE5Y2MwZDRmYzQ3NWU5ZmQ3NDhjZjk1MGM3NzBjEgsSBxCO-NuM-RoYAZIBJAoKcHJvamVjdF9pZBIWQhQxMTg3MjA0Mzk0NjY1OTk3OTg4NQ&filename=&opi=89354086"
    "6_library2.html" = "https://contribution.usercontent.google.com/download?c=CgthaWRhX2NvZGVmeBJ8Eh1hcHBfY29tcGFuaW9uX2dlbmVyYXRlZF9maWxlcxpbCiVodG1sXzAwMDY1NjAyMTJlZTY1YmMwODE2ZmRlYzVlMTgzNzgyEgsSBxCO-NuM-RoYAZIBJAoKcHJvamVjdF9pZBIWQhQxMTg3MjA0Mzk0NjY1OTk3OTg4NQ&filename=&opi=89354086"
    "7_nowplaying.html" = "https://contribution.usercontent.google.com/download?c=CgthaWRhX2NvZGVmeBJ8Eh1hcHBfY29tcGFuaW9uX2dlbmVyYXRlZF9maWxlcxpbCiVodG1sXzAwMDY1NjAyMjk0YWUzZDUwOTI1ZDMxN2ZkMjc0MjhiEgsSBxCO-NuM-RoYAZIBJAoKcHJvamVjdF9pZBIWQhQxMTg3MjA0Mzk0NjY1OTk3OTg4NQ&filename=&opi=89354086"
    "8_albumdetails.html" = "https://contribution.usercontent.google.com/download?c=CgthaWRhX2NvZGVmeBJ8Eh1hcHBfY29tcGFuaW9uX2dlbmVyYXRlZF9maWxlcxpbCiVodG1sXzg4ODEwNzkxNmFmNzQ2ZDQ4NDFhYTA0YTVjZGZmNjI5EgsSBxCO-NuM-RoYAZIBJAoKcHJvamVjdF9pZBIWQhQxMTg3MjA0Mzk0NjY1OTk3OTg4NQ&filename=&opi=89354086"
    "9_settings.html" = "https://contribution.usercontent.google.com/download?c=CgthaWRhX2NvZGVmeBJ8Eh1hcHBfY29tcGFuaW9uX2dlbmVyYXRlZF9maWxlcxpbCiVodG1sXzAwMDY1NjAyMTJiYjZhMTcwNjM5NGJmYzc4MGY2NjQwEgsSBxCO-NuM-RoYAZIBJAoKcHJvamVjdF9pZBIWQhQxMTg3MjA0Mzk0NjY1OTk3OTg4NQ&filename=&opi=89354086"
}

foreach ($item in $urls.GetEnumerator()) {
    $filename = $item.Key
    $url = $item.Value
    Write-Host "Downloading $filename..."
    curl.exe -L -o "design_source/$filename" $url
}
Write-Host "Done downloading."
