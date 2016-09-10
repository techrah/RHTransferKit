Pod::Spec.new do |s|
  s.name             = "RHTransferKit"
  s.version          = "1.0.4"
  s.summary          = "WebDAV downloading/uploading, FTP downloading."
  s.description      = <<-DESC
  Based on WTClient, a WebDAV client, the RHDownload class is capable of redirecting HTTP 301s, as well as pausing and resuming.
  The FTP Client is based solely on Core Foundation streams and is capable of resuming downloads.
                       DESC
  s.homepage         = "https://github.com/ryanhomer/RHTransferKit"
  s.license          = 'MIT'
  s.author           = { "Ryan Homer" => "ryan@murage.ca" }
  s.source           = { :git => "https://github.com/ryanhomer/RHTransferKit.git", :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/rah71'
  s.platform     = :ios, '4.0'
  s.requires_arc = false
  s.source_files = 'RHTransferKit/*.{h,m}', 'RHTransferKit/WebDAV/*.{h,m}'
  s.frameworks = 'Foundation', 'UIKit'
end
