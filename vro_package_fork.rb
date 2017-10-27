# Add the local directory to the library path
libdir = File.dirname(__FILE__)
$LOAD_PATH.unshift(libdir) unless $LOAD_PATH.include?(libdir)

require 'vro_package'

path_to_package = ARGV[0]
new_package_name = ARGV[1]

# Relocate workflows to a folder of the same name
new_category_name = new_package_name

package = VRO::Package.new(path_to_package)
package.fork(new_package_name, new_category_name)

